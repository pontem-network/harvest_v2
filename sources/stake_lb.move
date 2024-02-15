module harvest::stake_lb {
    // !!! FOR AUDITOR!!!
    // Look at math part of this module.
    use std::option::{Self, Option};
    use std::signer;
    use std::string::String;

    use aptos_std::event::{Self, EventHandle};
    use aptos_std::math64;
    use aptos_std::math128;
    use aptos_std::table;
    use aptos_std::table::Table;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;

    use aptos_token::token::{Self, Token};

    use harvest::stake_config;

    //
    // Errors
    //

    /// Pool does not exist.
    const ERR_NO_POOL: u64 = 100;

    /// Pool already exists.
    const ERR_POOL_ALREADY_EXISTS: u64 = 101;

    /// Pool reward can't be zero.
    const ERR_REWARD_CANNOT_BE_ZERO: u64 = 102;

    /// User has no stake.
    const ERR_NO_STAKE: u64 = 103;

    /// Not enough S balance to unstake
    const ERR_NOT_ENOUGH_S_BALANCE: u64 = 104;

    /// Amount can't be zero.
    const ERR_AMOUNT_CANNOT_BE_ZERO: u64 = 105;

    /// Nothing to harvest yet.
    const ERR_NOTHING_TO_HARVEST: u64 = 106;

    /// CoinType is not a coin.
    const ERR_IS_NOT_COIN: u64 = 107;

    /// Cannot unstake before lockup period end.
    const ERR_TOO_EARLY_UNSTAKE: u64 = 108;

    /// The pool is in the "emergency state", all operations except for the `emergency_unstake()` are disabled.
    const ERR_EMERGENCY: u64 = 109;

    /// The pool is not in "emergency state".
    const ERR_NO_EMERGENCY: u64 = 110;

    /// Only one hardcoded account can enable "emergency state" for the pool, it's not the one.
    const ERR_NOT_ENOUGH_PERMISSIONS_FOR_EMERGENCY: u64 = 111;

    /// Duration can't be zero.
    const ERR_DURATION_CANNOT_BE_ZERO: u64 = 112;

    /// When harvest finished for a pool.
    const ERR_HARVEST_FINISHED: u64 = 113;

    /// When withdrawing at wrong period.
    const ERR_NOT_WITHDRAW_PERIOD: u64 = 114;

    /// When not treasury withdrawing.
    const ERR_NOT_TREASURY: u64 = 115;

    /// When NFT collection does not exist.
    const ERR_NO_COLLECTION: u64 = 116;

    /// When boost percent is not in required range.
    const ERR_INVALID_BOOST_PERCENT: u64 = 117;

    /// When boosting stake in pool without specified nft collection.
    const ERR_NON_BOOST_POOL: u64 = 118;

    /// When boosting same stake again.
    const ERR_ALREADY_BOOSTED: u64 = 119;

    /// When token collection not match pool.
    const ERR_WRONG_TOKEN_COLLECTION: u64 = 120;

    /// When removing boost from non boosted stake.
    const ERR_NO_BOOST: u64 = 121;

    /// When amount of NFT for boost is more than one.
    const ERR_NFT_AMOUNT_MORE_THAN_ONE: u64 = 122;

    /// When reward coin has more than 10 decimals.
    const ERR_INVALID_REWARD_DECIMALS: u64 = 123;

    /// When provided LB tokens has a wrong creator.
    const ERR_WRONG_TOKEN_CREATOR: u64 = 124;

    /// The amount of output from the stack is more than staking amount
    const ERR_AMOUNT_EXCEED_BALANCE: u64 = 125;

    /// Pool does not exist.
    const ERR_NO_POOLS: u64 = 126;

    //
    // Constants
    //

    /// Week in seconds, lockup period.
    const WEEK_IN_SECONDS: u64 = 604800;

    /// When treasury can withdraw rewards (~3 months).
    const WITHDRAW_REWARD_PERIOD_IN_SECONDS: u64 = 7257600;

    /// Minimum percent of stake increase on boost.
    const MIN_NFT_BOOST_PRECENT: u128 = 1;

    /// Maximum percent of stake increase on boost.
    const MAX_NFT_BOOST_PERCENT: u128 = 100;

    /// Scale of pool accumulated reward field.
    const ACCUM_REWARD_SCALE: u128 = 1000000000000;

    //
    // Core data structures
    //

    struct Pools<phantom R> has key {
        // Collection name -> Stake pool
        pools: Table<String, StakePool<R>>,
    }

    /// Stake pool, stores stake, reward coins and related info.
    struct StakePool<phantom R> has store {
        reward_per_sec: u64,
        // pool reward ((reward_per_sec * time) / total_staked) + accum_reward (previous period)
        accum_reward: u128,
        // last accum_reward update time
        last_updated: u64,
        // start timestamp.
        start_timestamp: u64,
        // when harvest will be finished.
        end_timestamp: u64,

        stakes: Table<address, UserStake>,
        stake_token: Option<Token>,
        reward_coins: Coin<R>,
        // multiplier to handle decimals
        scale: u128,

        total_boosted: u128,

        /// This field can contain pool boost configuration.
        /// Pool creator can give ability for users to increase their stake profitability
        /// by staking nft's from specified collection.
        nft_boost_config: Option<NFTBoostConfig>,

        /// This field set to `true` only in case of emergency:
        /// * only `emergency_unstake()` operation is available in the state of emergency
        emergency_locked: bool,

        stake_events: EventHandle<StakeEvent>,
        unstake_events: EventHandle<UnstakeEvent>,
        deposit_events: EventHandle<DepositRewardEvent>,
        harvest_events: EventHandle<HarvestEvent>,
        boost_events: EventHandle<BoostEvent>,
        remove_boost_events: EventHandle<RemoveBoostEvent>,
    }

    struct InitConfiguration has key {
        resource_signer_cap: SignerCapability,
    }

    /// Pool boost config with NFT collection info.
    struct NFTBoostConfig has store {
        boost_percent: u128,
        collection_owner: address,
        collection_name: String,
    }

    /// Stores user stake info.
    struct UserStake has store {
        amount: u64,
        // contains the value of rewards that cannot be harvested by the user
        unobtainable_reward: u128,
        earned_reward: u64,
        unlock_time: u64,
        // optionaly contains token that boosts stake
        nft: Option<Token>,
        boosted_amount: u128,
    }

    //
    // Public functions
    //

    /// Creates nft boost config that can be used for pool registration.
    ///     * `collection_owner` - address of nft collection creator.
    ///     * `collection_name` - nft collection name.
    ///     * `boost_percent` - percentage of increasing user stake "power" after nft stake.
    public fun create_boost_config(
        collection_owner: address,
        collection_name: String,
        boost_percent: u128
    ): NFTBoostConfig {
        assert!(token::check_collection_exists(collection_owner, collection_name), ERR_NO_COLLECTION);
        assert!(boost_percent >= MIN_NFT_BOOST_PRECENT, ERR_INVALID_BOOST_PERCENT);
        assert!(boost_percent <= MAX_NFT_BOOST_PERCENT, ERR_INVALID_BOOST_PERCENT);

        NFTBoostConfig {
            boost_percent,
            collection_owner,
            collection_name,
        }
    }

    /// Registering pool for specific coin.
    ///     * `owner` - pool creator account, under which the pool will be stored.
    ///     * `reward_coins` - R coins which are used in distribution as reward.
    ///     * `duration` - pool life duration, can be increased by depositing more rewards.
    ///     * `nft_boost_config` - optional boost configuration. Allows users to stake nft and get more rewards.
    public fun register_pool<R>(
        owner: &signer,
        stake_token: &Token,
        reward_coins: Coin<R>,
        duration: u64,
        nft_boost_config: Option<NFTBoostConfig>
    ) acquires Pools {
        let (token_creator, collection_name, _) =
            get_token_field(stake_token);

        assert!(token_creator == @liquidswap_v1_resource_account, ERR_WRONG_TOKEN_CREATOR);
        assert!(coin::is_coin_initialized<R>(), ERR_IS_NOT_COIN);
        assert!(!stake_config::is_global_emergency(), ERR_EMERGENCY);
        assert!(duration > 0, ERR_DURATION_CANNOT_BE_ZERO);

        let reward_per_sec = coin::value(&reward_coins) / duration;
        assert!(reward_per_sec > 0, ERR_REWARD_CANNOT_BE_ZERO);

        let current_time = timestamp::now_seconds();
        let end_timestamp = current_time + duration;

        let origin_decimals = (coin::decimals<R>() as u128);
        let stake_token_decimals = (3 as u128);
        assert!(origin_decimals <= 10, ERR_INVALID_REWARD_DECIMALS);

        let reward_scale = ACCUM_REWARD_SCALE / math128::pow(10, origin_decimals);
        // let stake_scale = math128::pow(10, (coin::decimals<S>() as u128));
        let stake_scale = math128::pow(10, (stake_token_decimals));
        // let stake_scale = 1;
        let scale = stake_scale * reward_scale;

        let pool = StakePool<R> {
            reward_per_sec,
            accum_reward: 0,
            last_updated: current_time,
            start_timestamp: current_time,
            end_timestamp,
            stakes: table::new(),
            stake_token: option::none(),
            reward_coins,
            scale,
            total_boosted: 0,
            nft_boost_config,
            emergency_locked: false,
            stake_events: account::new_event_handle<StakeEvent>(owner),
            unstake_events: account::new_event_handle<UnstakeEvent>(owner),
            deposit_events: account::new_event_handle<DepositRewardEvent>(owner),
            harvest_events: account::new_event_handle<HarvestEvent>(owner),
            boost_events: account::new_event_handle<BoostEvent>(owner),
            remove_boost_events: account::new_event_handle<RemoveBoostEvent>(owner),
        };

        if (exists<Pools<R>>(signer::address_of(owner))) {
            let pools_mut = &mut borrow_global_mut<Pools<R>>(signer::address_of(owner)).pools;
            assert!(!table::contains(pools_mut, collection_name), ERR_POOL_ALREADY_EXISTS);
            table::add(pools_mut, collection_name, pool);
        } else {
            let pools = table::new<String, StakePool<R>>();
            table::add(&mut pools, collection_name, pool);
            move_to(owner, Pools<R> {
                pools
            });
        };
    }

    /// Depositing reward coins to specific pool, updates pool duration.
    ///     * `depositor` - rewards depositor account.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `coins` - R coins which are used in distribution as reward.
    public fun deposit_reward_coins<R>(
        depositor: &signer,
        pool_addr: address,
        collection_name: String,
        coins: Coin<R>
    ) acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);
        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        // let pool = borrow_global_mut<StakePool<R>>(pool_addr);
        let pool = table::borrow_mut(pools, collection_name);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        // it's forbidden to deposit more rewards (extend pool duration) after previous pool duration passed
        // preventing unfair reward distribution
        assert!(!is_finished_inner(pool), ERR_HARVEST_FINISHED);

        let amount = coin::value(&coins);
        assert!(amount > 0, ERR_AMOUNT_CANNOT_BE_ZERO);

        let additional_duration = amount / pool.reward_per_sec;
        assert!(additional_duration > 0, ERR_DURATION_CANNOT_BE_ZERO);

        pool.end_timestamp = pool.end_timestamp + additional_duration;

        coin::merge(&mut pool.reward_coins, coins);

        let depositor_addr = signer::address_of(depositor);

        event::emit_event<DepositRewardEvent>(
            &mut pool.deposit_events,
            DepositRewardEvent {
                user_address: depositor_addr,
                amount,
                new_end_timestamp: pool.end_timestamp,
            },
        );
    }

    /// Stakes user coins in pool.
    ///     * `user` - account that making a stake.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `token` - LB token that will be staked in pool.
    public fun stake<R>(
        user: &signer,
        pool_addr: address,
        token: Token
    ) acquires Pools {
        let amount = token::get_token_amount(&token);
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        let (_, collection_name, _) = get_token_field(&token);

        assert!(amount > 0, ERR_AMOUNT_CANNOT_BE_ZERO);
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow_mut(pools, collection_name);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);
        assert!(!is_finished_inner(pool), ERR_HARVEST_FINISHED);

        // update pool accum_reward and timestamp
        update_accum_reward(pool);

        let current_time = timestamp::now_seconds();
        let user_address = signer::address_of(user);
        let accum_reward = pool.accum_reward;

        if (!table::contains(&pool.stakes, user_address)) {
            let new_stake = UserStake {
                amount,
                unobtainable_reward: 0,
                earned_reward: 0,
                unlock_time: current_time + WEEK_IN_SECONDS,
                nft: option::none(),
                boosted_amount: 0,
            };

            // calculate unobtainable reward for new stake
            new_stake.unobtainable_reward = (accum_reward * (amount as u128)) / pool.scale;
            table::add(&mut pool.stakes, user_address, new_stake);
        } else {
            let user_stake = table::borrow_mut(&mut pool.stakes, user_address);

            // update earnings
            update_user_earnings(accum_reward, pool.scale, user_stake);

            user_stake.amount = user_stake.amount + amount;

            if (option::is_some(&user_stake.nft)) {
                let boost_percent = option::borrow(&pool.nft_boost_config).boost_percent;

                pool.total_boosted = pool.total_boosted - user_stake.boosted_amount;
                // calculate user boosted_amount using u128 to prevent overflow
                user_stake.boosted_amount = ((user_stake.amount as u128) * boost_percent) / 100;
                pool.total_boosted = pool.total_boosted + user_stake.boosted_amount;
            };

            // recalculate unobtainable reward after stake amount changed
            user_stake.unobtainable_reward =
                (accum_reward * user_stake_amount_with_boosted(user_stake)) / pool.scale;

            user_stake.unlock_time = current_time + WEEK_IN_SECONDS;
        };

        if (option::is_some(&pool.stake_token)) {
            let stake_token = option::borrow_mut(&mut pool.stake_token);
            token::merge(stake_token, token);
        } else {
            option::fill(&mut pool.stake_token, token);
        };

        event::emit_event<StakeEvent>(
            &mut pool.stake_events,
            StakeEvent { user_address, amount },
        );
    }

    /// Unstakes user coins from pool.
    ///     * `user` - account that owns stake.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `amount` - a number of S coins to unstake.
    /// Returns S coins: `Coin<S>`.
    public fun unstake<R>(
        user: &signer,
        pool_addr: address,
        collection_name: String,
        amount: u64
    ): Token acquires Pools {
        assert!(amount > 0, ERR_AMOUNT_CANNOT_BE_ZERO);
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow_mut(pools, collection_name);
        assert!(option::is_some(&pool.stake_token), ERR_NO_STAKE);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);
        // assert!(token::get_token_amount(option::borrow(&pool.stake_token)) >= amount, ERR_AMOUNT_EXCEED_BALANCE);

        let user_address = signer::address_of(user);
        assert!(table::contains(&pool.stakes, user_address), ERR_NO_STAKE);

        // update pool accum_reward and timestamp
        update_accum_reward(pool);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
        assert!(amount <= user_stake.amount, ERR_NOT_ENOUGH_S_BALANCE);

        // check unlock timestamp
        let current_time = timestamp::now_seconds();
        if (pool.end_timestamp >= current_time) {
            assert!(current_time >= user_stake.unlock_time, ERR_TOO_EARLY_UNSTAKE);
        };

        // update earnings
        update_user_earnings(pool.accum_reward, pool.scale, user_stake);

        user_stake.amount = user_stake.amount - amount;

        if (option::is_some(&user_stake.nft)) {
            let boost_percent = option::borrow(&pool.nft_boost_config).boost_percent;

            pool.total_boosted = pool.total_boosted - user_stake.boosted_amount;
            // calculate user boosted_amount using u128 to prevent overflow
            user_stake.boosted_amount = ((user_stake.amount as u128) * boost_percent) / 100;
            pool.total_boosted = pool.total_boosted + user_stake.boosted_amount;
        };

        // recalculate unobtainable reward after stake amount changed
        user_stake.unobtainable_reward =
            (pool.accum_reward * user_stake_amount_with_boosted(user_stake)) / pool.scale;

        event::emit_event<UnstakeEvent>(
            &mut pool.unstake_events,
            UnstakeEvent { user_address, amount },
        );

        let stake_token = option::borrow_mut(&mut pool.stake_token);
        if (token::get_token_amount(stake_token) == amount) {
            option::extract(&mut pool.stake_token)
        } else {
            token::split(stake_token, amount)
        }
    }

    /// Harvests user reward.
    ///     * `user` - stake owner account.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns R coins: `Coin<R>`.
    public fun harvest<R>(user: &signer, pool_addr: address, collection_name: String): Coin<R> acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow_mut(pools, collection_name);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        let user_address = signer::address_of(user);
        assert!(table::contains(&pool.stakes, user_address), ERR_NO_STAKE);

        // update pool accum_reward and timestamp
        update_accum_reward(pool);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);

        // update earnings
        update_user_earnings(pool.accum_reward, pool.scale, user_stake);

        let earned = user_stake.earned_reward;
        assert!(earned > 0, ERR_NOTHING_TO_HARVEST);

        user_stake.earned_reward = 0;

        event::emit_event<HarvestEvent>(
            &mut pool.harvest_events,
            HarvestEvent { user_address, amount: earned },
        );

        // !!!FOR AUDITOR!!!
        // Double check that always enough rewards.
        coin::extract(&mut pool.reward_coins, earned)
    }

    /// Boosts user stake with nft.
    ///     * `user` - stake owner account.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `nft` - token for stake boost.
    public fun boost<R>(user: &signer, pool_addr: address, collection_name: String, nft: Token) acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow_mut(pools, collection_name);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);
        assert!(option::is_some(&pool.nft_boost_config), ERR_NON_BOOST_POOL);

        let user_address = signer::address_of(user);
        assert!(table::contains(&pool.stakes, user_address), ERR_NO_STAKE);

        let token_amount = token::get_token_amount(&nft);
        assert!(token_amount == 1, ERR_NFT_AMOUNT_MORE_THAN_ONE);

        let token_id = token::get_token_id(&nft);
        let (token_collection_owner, token_collection_name, _, _) = token::get_token_id_fields(&token_id);

        let params = option::borrow(&pool.nft_boost_config);
        let boost_percent = params.boost_percent;
        let collection_owner = params.collection_owner;
        let collection_name = params.collection_name;

        // check nft is from correct collection
        assert!(token_collection_owner == collection_owner, ERR_WRONG_TOKEN_COLLECTION);
        assert!(token_collection_name == collection_name, ERR_WRONG_TOKEN_COLLECTION);

        // recalculate pool
        update_accum_reward(pool);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);

        // recalculate stake
        update_user_earnings(pool.accum_reward, pool.scale, user_stake);

        // check if stake boosted before
        assert!(option::is_none(&user_stake.nft), ERR_ALREADY_BOOSTED);

        option::fill(&mut user_stake.nft, nft);

        // update user stake and pool after stake boost using u128 to prevent overflow
        user_stake.boosted_amount = ((user_stake.amount as u128) * boost_percent) / 100;
        pool.total_boosted = pool.total_boosted + user_stake.boosted_amount;

        // recalculate unobtainable reward after stake boosted changed
        user_stake.unobtainable_reward =
            (pool.accum_reward * user_stake_amount_with_boosted(user_stake)) / pool.scale;

        event::emit_event(
            &mut pool.boost_events,
            BoostEvent { user_address },
        );
    }

    /// Removes nft boost.
    ///     * `user` - stake owner account.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns staked nft: `Token`.
    public fun remove_boost<R>(user: &signer, pool_addr: address, collection_name: String): Token acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow_mut(pools, collection_name);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        let user_address = signer::address_of(user);
        assert!(table::contains(&pool.stakes, user_address), ERR_NO_STAKE);

        // recalculate pool
        update_accum_reward(pool);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
        assert!(option::is_some(&user_stake.nft), ERR_NO_BOOST);

        // recalculate stake
        update_user_earnings(pool.accum_reward, pool.scale, user_stake);

        // update user stake and pool after nft claim
        pool.total_boosted = pool.total_boosted - user_stake.boosted_amount;
        user_stake.boosted_amount = 0;

        // recalculate unobtainable reward after stake boosted changed
        user_stake.unobtainable_reward =
            (pool.accum_reward * user_stake_amount_with_boosted(user_stake)) / pool.scale;

        event::emit_event(
            &mut pool.remove_boost_events,
            RemoveBoostEvent { user_address },
        );

        option::extract(&mut user_stake.nft)
    }

    /// Enables local "emergency state" for the specific `<S, R>` pool at `pool_addr`. Cannot be disabled.
    ///     * `admin` - current emergency admin account.
    ///     * `pool_addr` - address under which pool are stored.
    public fun enable_emergency<R>(admin: &signer, pool_addr: address, collection_name: String) acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        assert!(
            signer::address_of(admin) == stake_config::get_emergency_admin_address(),
            ERR_NOT_ENOUGH_PERMISSIONS_FOR_EMERGENCY
        );

        let pool = table::borrow_mut(pools, collection_name);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        pool.emergency_locked = true;
    }

    /// Withdraws all the user stake and nft from the pool. Only accessible in the "emergency state".
    ///     * `user` - user who has stake.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns staked coins `S` and optionaly nft: `Coin<S>`, `Option<Token>`.
    public fun emergency_unstake<R>(
        user: &signer,
        pool_addr: address,
        collection_name: String
    ): (Token, Option<Token>) acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow_mut(pools, collection_name);
        assert!(is_emergency_inner(pool), ERR_NO_EMERGENCY);

        let user_addr = signer::address_of(user);
        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        let user_stake = table::remove(&mut pool.stakes, user_addr);
        let UserStake {
            amount,
            unobtainable_reward: _,
            earned_reward: _,
            unlock_time: _,
            nft,
            boosted_amount: _
        } = user_stake;

        let stake_token = option::borrow_mut(&mut pool.stake_token);
        (token::split(stake_token, amount), nft)
    }

    /// If 3 months passed we can withdraw any remaining rewards using treasury account.
    /// In case of emergency we can withdraw to treasury immediately.
    ///     * `treasury` - treasury admin account.
    ///     * `pool_addr` - address of the pool.
    ///     * `amount` - rewards amount to withdraw.
    public fun withdraw_to_treasury<R>(
        treasury: &signer,
        pool_addr: address,
        collection_name: String,
        amount: u64
    ): Coin<R> acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        assert!(signer::address_of(treasury) == stake_config::get_treasury_admin_address(), ERR_NOT_TREASURY);

        let pool = table::borrow_mut(pools, collection_name);

        if (!is_emergency_inner(pool)) {
            let now = timestamp::now_seconds();
            assert!(now >= (pool.end_timestamp + WITHDRAW_REWARD_PERIOD_IN_SECONDS), ERR_NOT_WITHDRAW_PERIOD);
        };

        coin::extract(&mut pool.reward_coins, amount)
    }

    //
    // Getter functions
    //

    /// Get timestamp of pool creation.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns timestamp contains date when pool created.
    public fun get_start_timestamp<R>(pool_addr: address, collection_name: String): u64 acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);
        pool.start_timestamp
    }

    /// Checks if user can boost own stake in pool.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns true if pool accepts boosts.
    public fun is_boostable<R>(pool_addr: address, collection_name: String): bool acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);

        option::is_some(&pool.nft_boost_config)
    }

    /// Get NFT boost config parameters for pool.
    ///     * `pool_addr` - the pool with with NFT boost collection enabled.
    /// Returns both `collection_owner`, `collection_name` and boost percent.
    public fun get_boost_config<R>(
        pool_addr: address,
        collection_name: String
    ): (address, String, u128) acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);
        assert!(option::is_some(&pool.nft_boost_config), ERR_NON_BOOST_POOL);

        let boost_config = option::borrow(&pool.nft_boost_config);
        (boost_config.collection_owner, boost_config.collection_name, boost_config.boost_percent)
    }

    /// Checks if harvest on the pool finished.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns true if harvest finished for the pool.
    public fun is_finished<R>(pool_addr: address, collection_name: String): bool acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);
        is_finished_inner(pool)
    }

    /// Gets timestamp when harvest will be finished for the pool.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns timestamp.
    public fun get_end_timestamp<R>(pool_addr: address, collection_name: String): u64 acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);
        pool.end_timestamp
    }

    /// Checks if pool exists.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns true if pool exists.
    public fun pool_exists<R>(pool_addr: address, collection_name: String): bool acquires Pools {
        if (exists<Pools<R>>(pool_addr)) {
            let pools = &borrow_global<Pools<R>>(pool_addr).pools;
            table::contains(pools, collection_name)
        } else {
            false
        }
    }

    /// Checks if stake exists.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns true if stake exists.
    public fun stake_exists<R>(pool_addr: address, collection_name: String, user_addr: address): bool acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOL);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);

        table::contains(&pool.stakes, user_addr)
    }

    /// Checks current total staked amount in pool.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns total staked amount.
    public fun get_pool_total_stake<R>(pool_addr: address, collection_name: String): u64 acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);
        if (option::is_some(&pool.stake_token)) {
            let stake_token = option::borrow(&pool.stake_token);
            // coin::value(&borrow_global<StakePool<R>>(pool_addr).stake_token)
            token::get_token_amount(stake_token)
        } else {
            0
        }
    }

    /// Checks current total boosted amount in pool.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns total pool boosted amount.
    public fun get_pool_total_boosted<R>(pool_addr: address, collection_name: String): u128 acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        table::borrow(pools, collection_name).total_boosted
    }

    /// Checks current amount staked by user in specific pool.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns staked amount.
    public fun get_user_stake<R>(pool_addr: address, collection_name: String, user_addr: address): u64 acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);

        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        table::borrow(&pool.stakes, user_addr).amount
    }

    /// Checks if user user stake is boosted.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns true if stake is boosted.
    public fun is_boosted<R>(pool_addr: address, collection_name: String, user_addr: address): bool acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);

        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        option::is_some(&table::borrow(&pool.stakes, user_addr).nft)
    }

    /// Checks current user boosted amount in specific pool.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns user boosted amount.
    public fun get_user_boosted<R>(
        pool_addr: address,
        collection_name: String,
        user_addr: address
    ): u128 acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);

        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        table::borrow(&pool.stakes, user_addr).boosted_amount
    }

    /// Checks current pending user reward in specific pool.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns reward amount that can be harvested by stake owner.
    public fun get_pending_user_rewards<R>(
        pool_addr: address,
        collection_name: String,
        user_addr: address
    ): u64 acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);
        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        let user_stake = table::borrow(&pool.stakes, user_addr);
        let current_time = get_time_for_last_update(pool);
        let new_accum_rewards = accum_rewards_since_last_updated(pool, current_time);

        let earned_since_last_update = user_earned_since_last_update(
            pool.accum_reward + new_accum_rewards,
            pool.scale,
            user_stake,
        );
        user_stake.earned_reward + (earned_since_last_update as u64)
    }

    /// Checks stake unlock time in specific pool.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns stake unlock time.
    public fun get_unlock_time<R>(pool_addr: address, collection_name: String, user_addr: address): u64 acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);

        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        math64::min(pool.end_timestamp, table::borrow(&pool.stakes, user_addr).unlock_time)
    }

    /// Checks if stake is unlocked.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns true if user can unstake.
    public fun is_unlocked<R>(pool_addr: address, collection_name: String, user_addr: address): bool acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);

        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        let current_time = timestamp::now_seconds();
        let unlock_time = math64::min(pool.end_timestamp, table::borrow(&pool.stakes, user_addr).unlock_time);

        current_time >= unlock_time
    }

    /// Checks whether "emergency state" is enabled. In that state, only `emergency_unstake()` function is enabled.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns true if emergency happened (local or global).
    public fun is_emergency<R>(pool_addr: address, collection_name: String): bool acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);
        is_emergency_inner(pool)
    }

    /// Checks whether a specific `<S, R>` pool at the `pool_addr` has an "emergency state" enabled.
    ///     * `pool_addr` - address of the pool to check emergency.
    /// Returns true if local emergency enabled for pool.
    public fun is_local_emergency<R>(pool_addr: address, collection_name: String): bool acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);
        pool.emergency_locked
    }

    //
    // Private functions.
    //

    fun get_token_field(token: &Token): (address, String, String) {
        let token_id = token::get_token_id(token);
        let token_data_id = token::get_tokendata_id(token_id);
        token::get_token_data_id_fields(&token_data_id)
    }

    /// Checks if local pool or global emergency enabled.
    ///     * `pool` - pool to check emergency.
    /// Returns true of any kind or both of emergency enabled.
    fun is_emergency_inner<R>(pool: &StakePool<R>): bool {
        pool.emergency_locked || stake_config::is_global_emergency()
    }

    /// Internal function to check if harvest finished on the pool.
    ///     * `pool` - the pool itself.
    /// Returns true if harvest finished for the pool.
    fun is_finished_inner<R>(pool: &StakePool<R>): bool {
        let now = timestamp::now_seconds();
        now >= pool.end_timestamp
    }

    /// Calculates pool accumulated reward, updating pool.
    ///     * `pool` - pool to update rewards.
    fun update_accum_reward<R>(pool: &mut StakePool<R>) {
        let current_time = get_time_for_last_update(pool);
        let new_accum_rewards = accum_rewards_since_last_updated(pool, current_time);

        pool.last_updated = current_time;

        if (new_accum_rewards != 0) {
            pool.accum_reward = pool.accum_reward + new_accum_rewards;
        };
    }

    /// Calculates accumulated reward without pool update.
    ///     * `pool` - pool to calculate rewards.
    ///     * `current_time` - execution timestamp.
    /// Returns new accumulated reward.
    fun accum_rewards_since_last_updated<R>(pool: &StakePool<R>, current_time: u64): u128 {
        let seconds_passed = current_time - pool.last_updated;
        if (seconds_passed == 0) return 0;

        let total_boosted_stake = pool_total_staked_with_boosted(pool);
        if (total_boosted_stake == 0) return 0;

        let total_rewards =
            (pool.reward_per_sec as u128) * (seconds_passed as u128) * pool.scale;

        total_rewards / total_boosted_stake
    }

    /// Calculates user earnings, updating user stake.
    ///     * `accum_reward` - reward accumulated by pool.
    ///     * `scale` - multiplier to handle decimals.
    ///     * `user_stake` - stake to update earnings.
    fun update_user_earnings(accum_reward: u128, scale: u128, user_stake: &mut UserStake) {
        let earned =
            user_earned_since_last_update(accum_reward, scale, user_stake);
        user_stake.earned_reward = user_stake.earned_reward + (earned as u64);
        user_stake.unobtainable_reward = user_stake.unobtainable_reward + earned;
    }

    /// Calculates user earnings without stake update.
    ///     * `accum_reward` - reward accumulated by pool.
    ///     * `scale` - multiplier to handle decimals.
    ///     * `user_stake` - stake to update earnings.
    /// Returns new stake earnings.
    fun user_earned_since_last_update(
        accum_reward: u128,
        scale: u128,
        user_stake: &UserStake
    ): u128 {
        ((accum_reward * user_stake_amount_with_boosted(user_stake)) / scale)
            - user_stake.unobtainable_reward
    }

    /// Get time for last pool update: current time if the pool is not finished or end timmestamp.
    ///     * `pool` - pool to get time.
    /// Returns timestamp.
    fun get_time_for_last_update<R>(pool: &StakePool<R>): u64 {
        math64::min(pool.end_timestamp, timestamp::now_seconds())
    }

    /// Get total staked amount + boosted amount in the pool.
    ///     * `pool` - the pool itself.
    /// Returns amount.
    fun pool_total_staked_with_boosted<R>(pool: &StakePool<R>): u128 {
        if (option::is_some(&pool.stake_token)) {
            let stake_token = option::borrow(&pool.stake_token);
            (token::get_token_amount(stake_token) as u128) + pool.total_boosted
        } else {
            (0 as u128) + pool.total_boosted
        }
    }

    /// Get total staked amount + boosted amount by the user.
    ///     * `user_stake` - the user stake.
    /// Returns amount.
    fun user_stake_amount_with_boosted(user_stake: &UserStake): u128 {
        (user_stake.amount as u128) + user_stake.boosted_amount
    }

    //
    // Events
    //

    struct StakeEvent has drop, store {
        user_address: address,
        amount: u64,
    }

    struct UnstakeEvent has drop, store {
        user_address: address,
        amount: u64,
    }

    struct BoostEvent has drop, store {
        user_address: address
    }

    struct RemoveBoostEvent has drop, store {
        user_address: address
    }

    struct DepositRewardEvent has drop, store {
        user_address: address,
        amount: u64,
        new_end_timestamp: u64,
    }

    struct HarvestEvent has drop, store {
        user_address: address,
        amount: u64,
    }

    #[test_only]
    /// Access unobtainable_reward field in user stake.
    public fun get_unobtainable_reward<R>(
        pool_addr: address,
        collection_name: String,
        user_addr: address
    ): u128 acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);

        table::borrow(&pool.stakes, user_addr).unobtainable_reward
    }

    #[test_only]
    /// Access staking pool fields with no getters.
    public fun get_pool_info<R>(
        pool_addr: address,
        collection_name: String
    ): (u64, u128, u64, u64, u128) acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &borrow_global<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow(pools, collection_name);

        (pool.reward_per_sec, pool.accum_reward, pool.last_updated,
            coin::value<R>(&pool.reward_coins), pool.scale)
    }

    #[test_only]
    /// Force pool & user stake recalculations.
    public fun recalculate_user_stake<R>(
        pool_addr: address,
        collection_name: String,
        user_addr: address
    ) acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow_mut(pools, collection_name);
        update_accum_reward(pool);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_addr);
        update_user_earnings(pool.accum_reward, pool.scale, user_stake);
    }
}
