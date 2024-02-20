module harvest::stake {
    // !!! FOR AUDITOR!!!
    // Look at math part of this module.
    use std::option::{Self, Option};
    use std::signer;
    use std::string;
    use std::string::String;
    use std::vector;

    use aptos_std::event::{Self, EventHandle};
    use aptos_std::math64;
    use aptos_std::math128;
    use aptos_std::table;
    use aptos_std::table::Table;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;
    use aptos_token::property_map;

    use aptos_token::token::{Self, Token, TokenId};

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

    /// When withdrawing at wrong period.
    const ERR_NOT_WITHDRAW_PERIOD: u64 = 113;

    /// When not treasury withdrawing.
    const ERR_NOT_TREASURY: u64 = 114;

    /// When NFT collection does not exist.
    const ERR_NO_COLLECTION: u64 = 115;

    /// When boost percent is not in required range.
    const ERR_INVALID_BOOST_PERCENT: u64 = 116;

    /// When boosting stake in pool without specified nft collection.
    const ERR_NON_BOOST_POOL: u64 = 117;

    /// When boosting same stake again.
    const ERR_ALREADY_BOOSTED: u64 = 118;

    /// When token collection not match pool.
    const ERR_WRONG_TOKEN_COLLECTION: u64 = 119;

    /// When removing boost from non boosted stake.
    const ERR_NO_BOOST: u64 = 120;

    /// When amount of NFT for boost is more than one.
    const ERR_NFT_AMOUNT_MORE_THAN_ONE: u64 = 121;

    /// When reward coin has more than 10 decimals.
    const ERR_INVALID_REWARD_DECIMALS: u64 = 122;

    /// When provided LB tokens has a wrong creator.
    const ERR_WRONG_TOKEN_CREATOR: u64 = 123;

    /// Pool does not exist.
    const ERR_NO_POOLS: u64 = 124;

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

    struct Epoch<phantom R> has store {
        rewards_amount: u64,
        reward_per_sec: u64,
        // pool reward ((reward_per_sec * time) / total_staked) + accum_reward (previous period)
        accum_reward: u128,

        // start timestamp
        start_time: u64,
        // last accum_reward update time
        last_update_time: u64,
        end_time: u64,

        // stats
        distributed: u64,
        ended_at: u64,

        // tmp
        is_ghost: bool,
    }

    /// Stake pool, stores stake, reward coins and related info.
    struct StakePool<phantom S, phantom R> has key {
        current_epoch: u64, // todo: max vec len
        epochs: vector<Epoch<R>>,

        stakes: table::Table<address, UserStake>,
        stake_coins: Coin<S>,
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
        unobtainable_rewards: vector<u128>,
        earned_reward: u64,
        unlock_time: u64,
        // optionaly contains token that boosts stake
        nft: Option<Token>,
        boosted_amount: u128,
    }

    //
    // LB stake structs
    //

    struct Pools<phantom R> has key {
        // Collection name -> Stake pool
        pools: Table<String, StakeLbPool<R>>,
    }

    /// Stake pool, stores stake, reward coins and related info.
    struct StakeLbPool<phantom R> has store {
        current_epoch: u64,
        epochs: vector<Epoch<R>>,

        stakes: Table<address, UserLbStake>,
        // Bin ID => Token
        stake_tokens: Table<u64, Token>,
        reward_coins: Coin<R>,
        amounts: u128,
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

    /// Stores user stake info.
    struct UserLbStake has store {
        // bin_id => amount
        stakes: Table<u64, u64>,
        // contains the value of rewards that cannot be harvested by the user
        unobtainable_rewards: vector<u128>,
        earned_reward: u64,
        unlock_time: u64,
        // optionaly contains token that boosts stake
        nft: Option<Token>,
        // stores the total amount of stake tokens
        amounts: u128,
        boosted_amount: u128,
        bin_ids: vector<u64>,
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
    public fun register_pool<S, R>(
        owner: &signer,
        reward_coins: Coin<R>,
        duration: u64,
        nft_boost_config: Option<NFTBoostConfig>
    ) {
        assert!(!exists<StakePool<S, R>>(signer::address_of(owner)), ERR_POOL_ALREADY_EXISTS);
        assert!(coin::is_coin_initialized<S>() && coin::is_coin_initialized<R>(), ERR_IS_NOT_COIN);
        assert!(!stake_config::is_global_emergency(), ERR_EMERGENCY);
        assert!(duration > 0, ERR_DURATION_CANNOT_BE_ZERO);

        let rewards_amount = coin::value(&reward_coins);
        let reward_per_sec = rewards_amount / duration;
        assert!(reward_per_sec > 0, ERR_REWARD_CANNOT_BE_ZERO);

        let current_time = timestamp::now_seconds();
        let end_timestamp = current_time + duration;

        let origin_decimals = (coin::decimals<R>() as u128);
        assert!(origin_decimals <= 10, ERR_INVALID_REWARD_DECIMALS);

        let reward_scale = ACCUM_REWARD_SCALE / math128::pow(10, origin_decimals);
        let stake_scale = math128::pow(10, (coin::decimals<S>() as u128));
        let scale = stake_scale * reward_scale;

        let epoch = Epoch {
            rewards_amount,

            reward_per_sec,
            accum_reward: 0,

            start_time: current_time,
            last_update_time: current_time,
            end_time: end_timestamp,

            distributed: 0,
            ended_at: 0,

            is_ghost: false
        };

        let pool = StakePool<S, R> {
            current_epoch: 0,
            epochs: vector[epoch],

            stakes: table::new(),
            stake_coins: coin::zero(),
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
        move_to(owner, pool);
    }

    /// Registering pool for specific coin.
    ///     * `owner` - pool creator account, under which the pool will be stored.
    ///     * `stake_token` - token that will be used for staking.
    ///     * `reward_coins` - R coins which are used in distribution as reward.
    ///     * `duration` - pool life duration, can be increased by depositing more rewards.
    ///     * `nft_boost_config` - optional boost configuration. Allows users to stake nft and get more rewards.
    public fun register_lb_pool<R>(
        owner: &signer,
        stake_token: &Token,
        reward_coins: Coin<R>,
        duration: u64,
        nft_boost_config: Option<NFTBoostConfig>
    ) acquires Pools {
        let (token_creator, collection_name, _) =
            get_token_fields(stake_token);

        assert!(token_creator == @liquidswap_v1_resource_account, ERR_WRONG_TOKEN_CREATOR);
        assert!(coin::is_coin_initialized<R>(), ERR_IS_NOT_COIN);
        assert!(!stake_config::is_global_emergency(), ERR_EMERGENCY);
        assert!(duration > 0, ERR_DURATION_CANNOT_BE_ZERO);

        let rewards_amount = coin::value(&reward_coins);
        let reward_per_sec = rewards_amount / duration;
        assert!(reward_per_sec > 0, ERR_REWARD_CANNOT_BE_ZERO);

        let current_time = timestamp::now_seconds();
        let end_timestamp = current_time + duration;

        let origin_decimals = (coin::decimals<R>() as u128);
        let stake_token_decimals = (0 as u128);
        assert!(origin_decimals <= 10, ERR_INVALID_REWARD_DECIMALS);

        let reward_scale = ACCUM_REWARD_SCALE / math128::pow(10, origin_decimals);
        let stake_scale = math128::pow(10, (stake_token_decimals));
        let scale = stake_scale * reward_scale;

        let epoch = Epoch {
            rewards_amount,
            reward_per_sec,
            accum_reward: 0,
            start_time: current_time,
            last_update_time: current_time,
            end_time: end_timestamp,
            distributed: 0,
            ended_at: 0,
            is_ghost: false
        };

        let pool = StakeLbPool<R> {
            current_epoch: 0,
            epochs: vector[epoch],
            stakes: table::new(),
            stake_tokens: table::new(),
            amounts: 0,
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
            let pools = table::new<String, StakeLbPool<R>>();
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
    ///     * `duration` - new pool life duration.
    public fun deposit_reward_coins<S, R>(
        depositor: &signer,
        pool_addr: address,
        coins: Coin<R>,
        duration: u64,
    ) acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);
        assert!(duration > 0, ERR_DURATION_CANNOT_BE_ZERO);

        let pool = borrow_global_mut<StakePool<S, R>>(pool_addr);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        let amount = coin::value(&coins);
        assert!(amount > 0, ERR_AMOUNT_CANNOT_BE_ZERO);

        // update epoch
        update_accum_reward(pool);

        let current_time = timestamp::now_seconds();
        let epochs = &mut pool.epochs;
        let epoch = vector::borrow_mut(epochs, pool.current_epoch);

        let undistrib_rewards_amount = 0;

        // close ghost epoch or redirect rewards from reward epoch
        if (epoch.reward_per_sec == 0) {
            epoch.ended_at = current_time;
            epoch.end_time = current_time;
        } else {
            let epoch_time_left = epoch.end_time - epoch.last_update_time;

            // get undistributed rewards from prev epoch
            if (epoch_time_left > 0) {
                undistrib_rewards_amount = epoch.rewards_amount - epoch.distributed;
            };

            // finish current epoch
            epoch.ended_at = current_time;
        };

        // merge undistributed & curr rewards into new reward_per_sec
        let total_rewards = coin::value(&coins) + undistrib_rewards_amount;
        let reward_per_sec = total_rewards / duration;
        assert!(reward_per_sec > 0, ERR_REWARD_CANNOT_BE_ZERO);

        // add new rewards to pool
        coin::merge(&mut pool.reward_coins, coins);

        // create new epoch
        let epoch_duration = current_time + duration;
        let next_epoch = Epoch<R> {
            rewards_amount: total_rewards,

            reward_per_sec,
            accum_reward: 0,

            start_time: current_time,
            last_update_time: current_time,
            end_time: epoch_duration,

            distributed: 0,
            ended_at: 0,

            is_ghost: false
        };

        vector::push_back(epochs, next_epoch);
        pool.current_epoch = pool.current_epoch + 1;

        let depositor_addr = signer::address_of(depositor);
        event::emit_event<DepositRewardEvent>(
            &mut pool.deposit_events,
            DepositRewardEvent {
                user_address: depositor_addr,
                new_amount: amount,
                prev_amount: undistrib_rewards_amount,
                epoch_duration,
            },
        );
    }

    /// Depositing reward coins to specific pool, updates pool duration.
    ///     * `depositor` - rewards depositor account.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `coins` - R coins which are used in distribution as reward.
    public fun deposit_lb_reward_coins<R>(
        depositor: &signer,
        pool_addr: address,
        collection_name: String,
        coins: Coin<R>,
        duration: u64
    ) acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);
        assert!(duration > 0, ERR_DURATION_CANNOT_BE_ZERO);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow_mut(pools, collection_name);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        let amount = coin::value(&coins);
        assert!(amount > 0, ERR_AMOUNT_CANNOT_BE_ZERO);

        // update epoch
        update_lb_accum_reward(pool);

        let current_time = timestamp::now_seconds();
        let epochs = &mut pool.epochs;
        let epoch = vector::borrow_mut(epochs, pool.current_epoch);

        let undistrib_rewards_amount = 0;

        // close ghost epoch or redirect rewards from reward epoch
        if (epoch.reward_per_sec == 0) {
            epoch.ended_at = current_time;
            epoch.end_time = current_time;
        } else {
            let epoch_time_left = epoch.end_time - epoch.last_update_time;

            // get undistributed rewards from prev epoch
            if (epoch_time_left > 0) {
                undistrib_rewards_amount = epoch.rewards_amount - epoch.distributed;
            };

            // finish current epoch
            epoch.ended_at = current_time;
        };

        // merge undistributed & curr rewards into new reward_per_sec
        let total_rewards = coin::value(&coins) + undistrib_rewards_amount;
        let reward_per_sec = total_rewards / duration;
        assert!(reward_per_sec > 0, ERR_REWARD_CANNOT_BE_ZERO);

        coin::merge(&mut pool.reward_coins, coins);

        // create new epoch
        let epoch_duration = current_time + duration;
        let next_epoch = Epoch<R> {
            rewards_amount: total_rewards,
            reward_per_sec,
            accum_reward: 0,
            start_time: current_time,
            last_update_time: current_time,
            end_time: epoch_duration,
            distributed: 0,
            ended_at: 0,
            is_ghost: false
        };

        vector::push_back(epochs, next_epoch);
        pool.current_epoch = pool.current_epoch + 1;

        let depositor_addr = signer::address_of(depositor);

        event::emit_event<DepositRewardEvent>(
            &mut pool.deposit_events,
            DepositRewardEvent {
                user_address: depositor_addr,
                new_amount: amount,
                prev_amount: undistrib_rewards_amount,
                epoch_duration,
            },
        );
    }

    /// Stakes user coins in pool.
    ///     * `user` - account that making a stake.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `coins` - S coins that will be staked in pool.
    public fun stake<S, R>(
        user: &signer,
        pool_addr: address,
        coins: Coin<S>
    ) acquires StakePool {
        let amount = coin::value(&coins);
        assert!(amount > 0, ERR_AMOUNT_CANNOT_BE_ZERO);

        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global_mut<StakePool<S, R>>(pool_addr);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        // update pool accum_reward and timestamp
        update_accum_reward(pool);

        let current_time = timestamp::now_seconds();
        let user_address = signer::address_of(user);

        if (!table::contains(&pool.stakes, user_address)) {
            let new_stake = UserStake {
                amount,
                unobtainable_rewards: vector[],
                earned_reward: 0,
                unlock_time: current_time + WEEK_IN_SECONDS,
                nft: option::none(),
                boosted_amount: 0,
            };

            // calculate unobtainable reward for new stake
            let epoch_count = pool.current_epoch + 1;
            let epochs = &mut pool.epochs;
            let i = 0;
            while (i < epoch_count) {
                let accum_reward = vector::borrow(epochs, i).accum_reward;
                let unobt_rew = (accum_reward * (amount as u128)) / pool.scale;

                vector::push_back(&mut new_stake.unobtainable_rewards, unobt_rew);

                i = i + 1;
            };

            table::add(&mut pool.stakes, user_address, new_stake);
        } else {
            // update earnings
            update_earnings_epochs(pool, user_address);

            let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
            user_stake.amount = user_stake.amount + amount;

            if (option::is_some(&user_stake.nft)) {
                let boost_percent = option::borrow(&pool.nft_boost_config).boost_percent;

                pool.total_boosted = pool.total_boosted - user_stake.boosted_amount;
                // calculate user boosted_amount using u128 to prevent overflow
                user_stake.boosted_amount = ((user_stake.amount as u128) * boost_percent) / 100;
                pool.total_boosted = pool.total_boosted + user_stake.boosted_amount;
            };

            // recalculate unobtainable reward after stake amount changed
            update_unobtainable_reward(
                pool.scale,
                pool.current_epoch + 1,
                &pool.epochs,
                user_stake
            );

            user_stake.unlock_time = current_time + WEEK_IN_SECONDS;
        };

        coin::merge(&mut pool.stake_coins, coins);

        event::emit_event<StakeEvent>(
            &mut pool.stake_events,
            StakeEvent { user_address, amount },
        );
    }

    /// Stakes user coins in pool.
    ///     * `user` - account that making a stake.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `token` - LB token that will be staked in pool.
    public fun stake_lb<R>(
        user: &signer,
        pool_addr: address,
        token: Token
    ) acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let amount = token::get_token_amount(&token);
        assert!(amount > 0, ERR_AMOUNT_CANNOT_BE_ZERO);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        let token_id = token::get_token_id(&token);
        let token_data_id = token::get_tokendata_id(token_id);
        let (_, collection_name, _) = token::get_token_data_id_fields(&token_data_id);

        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow_mut(pools, collection_name);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        pool.amounts = pool.amounts + (amount as u128);

        // update pool accum_reward and timestamp
        update_lb_accum_reward(pool);

        let bin_id = get_bin_id(token_id);

        let current_time = timestamp::now_seconds();
        let user_address = signer::address_of(user);

        if (!table::contains(&pool.stakes, user_address)) {
            // Add a table to track the amount of staking
            let stakes = table::new<u64, u64>();
            table::add(&mut stakes, bin_id, amount);
            let new_stake = UserLbStake {
                stakes,
                unobtainable_rewards: vector[],
                earned_reward: 0,
                unlock_time: current_time + WEEK_IN_SECONDS,
                nft: option::none(),
                amounts: (amount as u128),
                boosted_amount: 0,
                bin_ids: vector[bin_id]
            };

            // calculate unobtainable reward for new stake
            let epoch_count = pool.current_epoch + 1;
            let epochs = &mut pool.epochs;
            let i = 0;
            while (i < epoch_count) {
                let accum_reward = vector::borrow(epochs, i).accum_reward;
                let unobt_rew = (accum_reward * (amount as u128)) / pool.scale;

                vector::push_back(&mut new_stake.unobtainable_rewards, unobt_rew);

                i = i + 1;
            };

            table::add(&mut pool.stakes, user_address, new_stake);
        } else {
            // update earnings
            update_lb_earnings_epochs(pool, user_address);

            // Add/update a table to track the amount of staking
            let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
            let user_amount;
            if (table::contains(&user_stake.stakes, bin_id)) {
                let current_token_amount = table::borrow_mut(&mut user_stake.stakes, bin_id);
                *current_token_amount = *current_token_amount + amount;
                user_amount = *current_token_amount;
            } else {
                table::add(&mut user_stake.stakes, bin_id, amount);
                user_amount = amount;
                vector::push_back(&mut user_stake.bin_ids, bin_id);
            };
            user_stake.amounts = user_stake.amounts + (amount as u128);


            if (option::is_some(&user_stake.nft)) {
                let boost_percent = option::borrow(&pool.nft_boost_config).boost_percent;

                pool.total_boosted = pool.total_boosted - user_stake.boosted_amount;
                // calculate user boosted_amount using u128 to prevent overflow
                user_stake.boosted_amount = ((user_amount as u128) * boost_percent) / 100;
                pool.total_boosted = pool.total_boosted + user_stake.boosted_amount;
            };

            // recalculate unobtainable reward after stake amount changed
            update_unobtainable_reward(
                pool.scale,
                pool.current_epoch + 1,
                &pool.epochs,
                user_stake
            );

            user_stake.unlock_time = current_time + WEEK_IN_SECONDS;
        };

        if (table::contains(&pool.stake_tokens, bin_id)) {
            let dst_token = table::borrow_mut(&mut pool.stake_tokens, bin_id);
            token::merge(dst_token, token);
        } else {
             table::add(&mut pool.stake_tokens, bin_id, token);
        };

        // let (suc, id) = vector::find(&pool.stake_tokens, |tk| token::get_token_id(tk) == token_id);
        // // If the token is already in 'stake_tokens', then we merge, if it is not there, then add
        // if (suc) {
        //     let dst_token = vector::borrow_mut(&mut pool.stake_tokens, id);
        //     token::merge(dst_token, token);
        // } else {
        //     vector::push_back(&mut pool.stake_tokens, token);
        // };

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
    public fun unstake<S, R>(
        user: &signer,
        pool_addr: address,
        amount: u64
    ): Coin<S> acquires StakePool {
        assert!(amount > 0, ERR_AMOUNT_CANNOT_BE_ZERO);
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global_mut<StakePool<S, R>>(pool_addr);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        let user_address = signer::address_of(user);
        assert!(table::contains(&pool.stakes, user_address), ERR_NO_STAKE);

        // update pool accum_reward and timestamp
        update_accum_reward(pool);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
        assert!(amount <= user_stake.amount, ERR_NOT_ENOUGH_S_BALANCE);

        // check unlock timestamp
        assert!(timestamp::now_seconds() >= user_stake.unlock_time, ERR_TOO_EARLY_UNSTAKE);

        // update earnings
        update_earnings_epochs(pool, user_address);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
        user_stake.amount = user_stake.amount - amount;

        if (option::is_some(&user_stake.nft)) {
            let boost_percent = option::borrow(&pool.nft_boost_config).boost_percent;

            pool.total_boosted = pool.total_boosted - user_stake.boosted_amount;
            // calculate user boosted_amount using u128 to prevent overflow
            user_stake.boosted_amount = ((user_stake.amount as u128) * boost_percent) / 100;
            pool.total_boosted = pool.total_boosted + user_stake.boosted_amount;
        };

        // recalculate unobtainable reward after stake amount changed
        update_unobtainable_reward(
            pool.scale,
            pool.current_epoch + 1,
            &pool.epochs,
            user_stake
        );

        event::emit_event<UnstakeEvent>(
            &mut pool.unstake_events,
            UnstakeEvent { user_address, amount },
        );

        coin::extract(&mut pool.stake_coins, amount)
    }

    /// Unstakes user coins from pool.
    ///     * `user` - account that owns stake.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `collection_name` - name of the collection to which the token belongs.
    ///     * `bin_id` - bin id of the LB token.
    ///     * `amount` - a number of S coins to unstake.
    /// Returns token: `Token`.
    public fun unstake_lb<R>(
        user: &signer,
        pool_addr: address,
        collection_name: String,
        bin_id: u64,
        amount: u64
    ): Token acquires Pools {
        assert!(amount > 0, ERR_AMOUNT_CANNOT_BE_ZERO);
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow_mut(pools, collection_name);

        // assert!(table::contains(&pool.stake_tokens, bin_id), ERR_NO_STAKE);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        let user_address = signer::address_of(user);
        assert!(table::contains(&pool.stakes, user_address), ERR_NO_STAKE);

        let user_stake = table::borrow(&mut pool.stakes, user_address);
        assert!(table::contains(&user_stake.stakes, bin_id), ERR_NO_STAKE);

        pool.amounts = pool.amounts - (amount as u128);

        // update pool accum_reward and timestamp
        update_lb_accum_reward(pool);

        let user_stake = table::borrow(&mut pool.stakes, user_address);
        let user_amount = *table::borrow(&mut user_stake.stakes, bin_id);

        assert!(amount <= user_amount, ERR_NOT_ENOUGH_S_BALANCE);

        // check unlock timestamp
        assert!(timestamp::now_seconds() >= user_stake.unlock_time, ERR_TOO_EARLY_UNSTAKE);

        // update earnings
        update_lb_earnings_epochs(pool, user_address);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
        let user_amount = *table::borrow_mut(&mut user_stake.stakes, bin_id);
        user_amount = user_amount - amount;
        user_stake.amounts = user_stake.amounts - (amount as u128);

        if (option::is_some(&user_stake.nft)) {
            let boost_percent = option::borrow(&pool.nft_boost_config).boost_percent;

            pool.total_boosted = pool.total_boosted - user_stake.boosted_amount;
            // calculate user boosted_amount using u128 to prevent overflow
            user_stake.boosted_amount = (user_stake.amounts * boost_percent) / 100;
            pool.total_boosted = pool.total_boosted + user_stake.boosted_amount;
        };

        // recalculate unobtainable reward after stake amount changed
        update_lb_unobtainable_reward(
            pool.scale,
            pool.current_epoch + 1,
            &pool.epochs,
            user_stake
        );

        if (user_amount == 0) {
            let (_, index) = vector::find(&user_stake.bin_ids, |bin| *bin == bin_id);
            vector::remove(&mut user_stake.bin_ids, index)
        };

        event::emit_event<UnstakeEvent>(
            &mut pool.unstake_events,
            UnstakeEvent { user_address, amount },
        );

        let token = table::borrow_mut(&mut pool.stake_tokens, bin_id);
        if (token::get_token_amount(token) == amount) {
            table::remove(&mut pool.stake_tokens, bin_id)
        } else {
            token::split(token, amount)
        }

        // Implementation for a stake token when it is a vector
        // let length = vector::length(&pool.stake_tokens) - 1;
        // for (i in 0..length) {
        //     let stored_token = vector::borrow_mut(&mut pool.stake_tokens, i);
        //     let stored_token_id = token::get_token_id(stored_token);
        //     let stored_bin_id = get_bin_id(stored_token_id);
        //     if (bin_id == stored_bin_id) {
        //         if (token::get_token_amount(stored_token) == amount) {
        //             table::remove(&mut pool.stake_tokens, i)
        //         } else {
        //             token::split(stored_token, amount)
        //         }
        //     };
        // }
        // let (suc, id) = vector::find(&pool.stake_tokens, |tk| token::get_token_id(tk) == token_id);
        // // If the token is already in 'stake_tokens', then we merge, if it is not there, then add
        // if (suc) {
        //     let dst_token = vector::borrow_mut(&mut pool.stake_tokens, id);
        //     token::merge(dst_token, token);
        // } else {
        //     vector::push_back(&mut pool.stake_tokens, token);
        // };
    }

    /// Harvests user reward.
    ///     * `user` - stake owner account.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns R coins: `Coin<R>`.
    public fun harvest<S, R>(user: &signer, pool_addr: address): Coin<R> acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global_mut<StakePool<S, R>>(pool_addr);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        let user_address = signer::address_of(user);
        assert!(table::contains(&pool.stakes, user_address), ERR_NO_STAKE);

        // update pool accum_reward and timestamp
        update_accum_reward(pool);

        // update earnings
        update_earnings_epochs(pool, user_address);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
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

    /// Harvests user reward.
    ///     * `user` - stake owner account.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `collection_name` - name of the collection to which the token belongs.
    ///     * `bin_id` - bin id of the LB token.
    /// Returns R coins: `Coin<R>`.
    public fun harvest_lb<R>(user: &signer, pool_addr: address, collection_name: String, bin_id: u64): Coin<R> acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow_mut(pools, collection_name);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        let user_address = signer::address_of(user);
        assert!(table::contains(&pool.stakes, user_address), ERR_NO_STAKE);

        let user_stake = table::borrow(&mut pool.stakes, user_address);
        assert!(table::contains(&user_stake.stakes, bin_id), ERR_NO_STAKE);

        // update pool accum_reward and timestamp
        update_lb_accum_reward(pool);

        // update earnings
        update_lb_earnings_epochs(pool, user_address);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
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
    public fun boost<S, R>(user: &signer, pool_addr: address, nft: Token) acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global_mut<StakePool<S, R>>(pool_addr);
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

        // update earnings
        update_earnings_epochs(pool, user_address);

        // check if stake boosted before
        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
        assert!(option::is_none(&user_stake.nft), ERR_ALREADY_BOOSTED);

        option::fill(&mut user_stake.nft, nft);

        // update user stake and pool after stake boost using u128 to prevent overflow
        user_stake.boosted_amount = ((user_stake.amount as u128) * boost_percent) / 100;
        pool.total_boosted = pool.total_boosted + user_stake.boosted_amount;

        // recalculate unobtainable reward after stake amount changed
        update_unobtainable_reward(
            pool.scale,
            pool.current_epoch + 1,
            &pool.epochs,
            user_stake
        );

        event::emit_event(
            &mut pool.boost_events,
            BoostEvent { user_address },
        );
    }

    /// Boosts user stake with nft.
    ///     * `user` - stake owner account.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `collection_name` - name of the collection to which the token belongs.
    ///     * `nft` - token for stake boost.
    public fun boost_lb<R>(user: &signer, pool_addr: address, collection_name: String, nft: Token) acquires Pools {
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

        let (token_collection_owner, token_collection_name, _, ) = get_token_fields(&nft);

        let params = option::borrow(&pool.nft_boost_config);
        let boost_percent = params.boost_percent;
        let collection_owner = params.collection_owner;
        let collection_name = params.collection_name;

        // check nft is from correct collection
        assert!(token_collection_owner == collection_owner, ERR_WRONG_TOKEN_COLLECTION);
        assert!(token_collection_name == collection_name, ERR_WRONG_TOKEN_COLLECTION);

        // recalculate pool
        update_lb_accum_reward(pool);

        // update earnings
        update_lb_earnings_epochs(pool, user_address);

        // check if stake boosted before
        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);

        assert!(option::is_none(&user_stake.nft), ERR_ALREADY_BOOSTED);

        option::fill(&mut user_stake.nft, nft);

        // update user stake and pool after stake boost using u128 to prevent overflow
        user_stake.boosted_amount = (user_stake.amounts * boost_percent) / 100;
        pool.total_boosted = pool.total_boosted + user_stake.boosted_amount;

        // recalculate unobtainable reward after stake amount changed
        update_lb_unobtainable_reward(
            pool.scale,
            pool.current_epoch + 1,
            &pool.epochs,
            user_stake
        );

        event::emit_event(
            &mut pool.boost_events,
            BoostEvent { user_address },
        );
    }

    /// Removes nft boost.
    ///     * `user` - stake owner account.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns staked nft: `Token`.
    public fun remove_boost<S, R>(user: &signer, pool_addr: address): Token acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global_mut<StakePool<S, R>>(pool_addr);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        let user_address = signer::address_of(user);
        assert!(table::contains(&pool.stakes, user_address), ERR_NO_STAKE);

        // recalculate pool
        update_accum_reward(pool);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
        assert!(option::is_some(&user_stake.nft), ERR_NO_BOOST);

        // update earnings
        update_earnings_epochs(pool, user_address);

        // update user stake and pool after nft claim
        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
        pool.total_boosted = pool.total_boosted - user_stake.boosted_amount;
        user_stake.boosted_amount = 0;

        // recalculate unobtainable reward after stake amount changed
        update_unobtainable_reward(
            pool.scale,
            pool.current_epoch + 1,
            &pool.epochs,
            user_stake
        );

        event::emit_event(
            &mut pool.remove_boost_events,
            RemoveBoostEvent { user_address },
        );

        option::extract(&mut user_stake.nft)
    }

    /// Removes nft boost.
    ///     * `user` - stake owner account.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `collection_name` - name of the collection to which the token belongs.
    /// Returns staked nft: `Token`.
    public fun remove_boost_lb<R>(user: &signer, pool_addr: address, collection_name: String): Token acquires Pools {
        assert!(exists<Pools<R>>(pool_addr), ERR_NO_POOLS);

        let pools = &mut borrow_global_mut<Pools<R>>(pool_addr).pools;
        assert!(table::contains(pools, collection_name), ERR_NO_POOL);

        let pool = table::borrow_mut(pools, collection_name);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        let user_address = signer::address_of(user);
        assert!(table::contains(&pool.stakes, user_address), ERR_NO_STAKE);

        // recalculate pool
        update_lb_accum_reward(pool);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
        assert!(option::is_some(&user_stake.nft), ERR_NO_BOOST);

        // update earnings
        update_lb_earnings_epochs(pool, user_address);

        // update user stake and pool after nft claim
        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);
        pool.total_boosted = pool.total_boosted - user_stake.boosted_amount;
        user_stake.boosted_amount = 0;

        // recalculate unobtainable reward after stake boosted changed
        update_lb_unobtainable_reward(
            pool.scale,
            pool.current_epoch + 1,
            &pool.epochs,
            user_stake
        );

        event::emit_event(
            &mut pool.remove_boost_events,
            RemoveBoostEvent { user_address },
        );

        option::extract(&mut user_stake.nft)
    }

    /// Enables local "emergency state" for the specific `<S, R>` pool at `pool_addr`. Cannot be disabled.
    ///     * `admin` - current emergency admin account.
    ///     * `pool_addr` - address under which pool are stored.
    public fun enable_emergency<S, R>(admin: &signer, pool_addr: address) acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);
        assert!(
            signer::address_of(admin) == stake_config::get_emergency_admin_address(),
            ERR_NOT_ENOUGH_PERMISSIONS_FOR_EMERGENCY
        );

        let pool = borrow_global_mut<StakePool<S, R>>(pool_addr);
        assert!(!is_emergency_inner(pool), ERR_EMERGENCY);

        pool.emergency_locked = true;
    }

    /// Withdraws all the user stake and nft from the pool. Only accessible in the "emergency state".
    ///     * `user` - user who has stake.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns staked coins `S` and optionaly nft: `Coin<S>`, `Option<Token>`.
    public fun emergency_unstake<S, R>(user: &signer, pool_addr: address): (Coin<S>, Option<Token>) acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global_mut<StakePool<S, R>>(pool_addr);
        assert!(is_emergency_inner(pool), ERR_NO_EMERGENCY);

        let user_addr = signer::address_of(user);
        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        let user_stake = table::remove(&mut pool.stakes, user_addr);
        let UserStake {
            amount,
            unobtainable_rewards: _,
            earned_reward: _,
            unlock_time: _,
            nft,
            boosted_amount: _
        } = user_stake;

        (coin::extract(&mut pool.stake_coins, amount), nft)
    }

    /// If 3 months passed we can withdraw any remaining rewards using treasury account.
    /// In case of emergency we can withdraw to treasury immediately.
    ///     * `treasury` - treasury admin account.
    ///     * `pool_addr` - address of the pool.
    ///     * `amount` - rewards amount to withdraw.
    public fun withdraw_to_treasury<S, R>(treasury: &signer, pool_addr: address, amount: u64): Coin<R> acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);
        assert!(signer::address_of(treasury) == stake_config::get_treasury_admin_address(), ERR_NOT_TREASURY);

        let pool = borrow_global_mut<StakePool<S, R>>(pool_addr);

        if (!is_emergency_inner(pool)) {
            let now = timestamp::now_seconds();
            let last_epoch_endtime = vector::borrow(&pool.epochs, pool.current_epoch).end_time;
            assert!(now >= (last_epoch_endtime + WITHDRAW_REWARD_PERIOD_IN_SECONDS), ERR_NOT_WITHDRAW_PERIOD);
        };

        coin::extract(&mut pool.reward_coins, amount)
    }

    //
    // Getter functions
    //

    #[view]
    /// Get timestamp of pool creation.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns timestamp contains date when pool created.
    public fun get_start_timestamp<S, R>(pool_addr: address): u64 acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        vector::borrow(&pool.epochs, 0).start_time
    }

    #[view]
    /// Checks if user can boost own stake in pool.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns true if pool accepts boosts.
    public fun is_boostable<S, R>(pool_addr: address): bool acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        option::is_some(&pool.nft_boost_config)
    }

    #[view]
    /// Get NFT boost config parameters for pool.
    ///     * `pool_addr` - the pool with with NFT boost collection enabled.
    /// Returns both `collection_owner`, `collection_name` and boost percent.
    public fun get_boost_config<S, R>(pool_addr: address): (address, String, u128)  acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        assert!(option::is_some(&pool.nft_boost_config), ERR_NON_BOOST_POOL);

        let boost_config = option::borrow(&pool.nft_boost_config);
        (boost_config.collection_owner, boost_config.collection_name, boost_config.boost_percent)
    }

    #[view]
    /// Gets timestamp when harvest will be finished for the pool.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns timestamp.
    public fun get_end_timestamp<S, R>(pool_addr: address): u64 acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        vector::borrow(&pool.epochs, pool.current_epoch).end_time
    }

    #[view]
    /// Checks if pool exists.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns true if pool exists.
    public fun pool_exists<S, R>(pool_addr: address): bool {
        exists<StakePool<S, R>>(pool_addr)
    }

    #[view]
    /// Checks if stake exists.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns true if stake exists.
    public fun stake_exists<S, R>(pool_addr: address, user_addr: address): bool acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        table::contains(&pool.stakes, user_addr)
    }

    #[view]
    /// Checks current total staked amount in pool.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns total staked amount.
    public fun get_pool_total_stake<S, R>(pool_addr: address): u64 acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        coin::value(&pool.stake_coins)
    }

    #[view]
    /// Checks current total boosted amount in pool.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns total pool boosted amount.
    public fun get_pool_total_boosted<S, R>(pool_addr: address): u128 acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        borrow_global<StakePool<S, R>>(pool_addr).total_boosted
    }

    #[view]
    /// Checks current epoch id in pool.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns epoch id.
    public fun get_pool_current_epoch<S, R>(pool_addr: address): u64 acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        borrow_global<StakePool<S, R>>(pool_addr).current_epoch
    }

    #[view]
    /// Checks current amount staked by user in specific pool.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns staked amount.
    public fun get_user_stake<S, R>(pool_addr: address, user_addr: address): u64 acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        table::borrow(&pool.stakes, user_addr).amount
    }

    #[view]
    /// Checks if user user stake is boosted.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns true if stake is boosted.
    public fun is_boosted<S, R>(pool_addr: address, user_addr: address): bool acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        option::is_some(&table::borrow(&pool.stakes, user_addr).nft)
    }

    #[view]
    /// Checks current user boosted amount in specific pool.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns user boosted amount.
    public fun get_user_boosted<S, R>(pool_addr: address, user_addr: address): u128 acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        table::borrow(&pool.stakes, user_addr).boosted_amount
    }

    #[view]
    /// Checks current pending user reward in specific pool.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns reward amount that can be harvested by stake owner.
    public fun get_pending_user_rewards<S, R>(pool_addr: address, user_addr: address): u64 acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global_mut<StakePool<S, R>>(pool_addr);
        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        let user_stake = table::borrow_mut(&mut pool.stakes, user_addr);
        let current_time = timestamp::now_seconds();

        let earnings = 0;
        let scale = pool.scale;
        let epoch_count = pool.current_epoch + 1;
        let epochs = &mut pool.epochs;
        let i = 0;
        while (i < epoch_count) {
            let epoch = vector::borrow_mut(epochs, i);

            // get new accum reward for last epoch
            let new_earnings = if (i + 1 == epoch_count) {
                let epoch_end_time = epoch.end_time;
                let reward_time = math64::min(epoch_end_time, current_time);

                let pool_total_staked_with_boosted =
                    (coin::value(&pool.stake_coins) as u128) + pool.total_boosted;
                let new_accum_rewards =
                    accum_rewards_since_last_updated(
                        pool_total_staked_with_boosted,
                        epoch.last_update_time,
                        epoch.reward_per_sec,
                        reward_time,
                        pool.scale
                    );
                let accum_reward = epoch.accum_reward + new_accum_rewards;
                user_earned_since_last_update(accum_reward, scale, user_stake, i)
            } else {
                user_earned_since_last_update(epoch.accum_reward, scale, user_stake, i)
            };
            earnings = earnings + new_earnings;
            i = i + 1;
        };

        user_stake.earned_reward + (earnings as u64)
    }

    #[view]
    /// Checks stake unlock time in specific pool.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns stake unlock time.
    public fun get_unlock_time<S, R>(pool_addr: address, user_addr: address): u64 acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        let current_epoch_endtime = vector::borrow(&pool.epochs, pool.current_epoch).end_time;
        // todo: remove epoch endtime dep
        math64::min(current_epoch_endtime, table::borrow(&pool.stakes, user_addr).unlock_time)
    }

    #[view]
    /// Checks if stake is unlocked.
    ///     * `pool_addr` - address under which pool are stored.
    ///     * `user_addr` - stake owner address.
    /// Returns true if user can unstake.
    public fun is_unlocked<S, R>(pool_addr: address, user_addr: address): bool acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        assert!(table::contains(&pool.stakes, user_addr), ERR_NO_STAKE);

        let current_time = timestamp::now_seconds();
        // todo: remove endtime dep
        let current_epoch_endtime = vector::borrow(&pool.epochs, pool.current_epoch).end_time;
        let unlock_time =
            math64::min(current_epoch_endtime, table::borrow(&pool.stakes, user_addr).unlock_time);

        current_time >= unlock_time
    }

    #[view]
    /// Checks whether "emergency state" is enabled. In that state, only `emergency_unstake()` function is enabled.
    ///     * `pool_addr` - address under which pool are stored.
    /// Returns true if emergency happened (local or global).
    public fun is_emergency<S, R>(pool_addr: address): bool acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        is_emergency_inner(pool)
    }

    #[view]
    /// Checks whether a specific `<S, R>` pool at the `pool_addr` has an "emergency state" enabled.
    ///     * `pool_addr` - address of the pool to check emergency.
    /// Returns true if local emergency enabled for pool.
    public fun is_local_emergency<S, R>(pool_addr: address): bool acquires StakePool {
        assert!(exists<StakePool<S, R>>(pool_addr), ERR_NO_POOL);

        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        pool.emergency_locked
    }

    //
    // Private functions.
    //

    /// Calculates unobtainable reward for user.
    ///     * `scale` - multiplier to handle decimals.
    ///     * `epoch_count` - count of epochs in pool.
    ///     * `epochs` - vector of pool epochs.
    ///     * `user_stake` - the user stake.
    fun update_lb_unobtainable_reward<R>(
        scale: u128,
        epoch_count: u64,
        epochs: &vector<Epoch<R>>,
        user_stake: &mut UserLbStake
    ) {
        let i = 0;
        while (i < epoch_count) {
            let accum_reward = vector::borrow(epochs, i).accum_reward;
            let unobt_rew = (accum_reward * user_stake_amount_with_boosted(user_stake)) / scale;

            let el = vector::borrow_mut(&mut user_stake.unobtainable_rewards, i);
            *el = unobt_rew;

            i = i + 1;
        };
    }


    /// Updates user earnings.
    ///     * `pool` - pool to get epochs and stakes.
    ///     * `user_address` - address of user to update earnings for.
    fun update_lb_earnings_epochs<R>(pool: &mut StakeLbPool<R>, user_address: address) {
        let epoch_count = pool.current_epoch + 1;
        let epochs = &mut pool.epochs;
        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);

        let i = 0;
        while (i < epoch_count) {
            let epoch = vector::borrow_mut(epochs, i);

            update_lb_user_earnings(epoch.accum_reward, pool.scale, user_stake, i);
            i = i + 1;
        };
    }

    /// Calculates user earnings, updating user stake.
    ///     * `accum_reward` - reward accumulated by pool.
    ///     * `scale` - multiplier to handle decimals.
    ///     * `user_stake` - stake to update earnings.
    fun update_lb_user_earnings(accum_reward: u128, scale: u128, user_stake: &mut UserLbStake, epoch: u64) {
        let earned =
            user_lb_earned_since_last_update(accum_reward, scale, user_stake, epoch);
        user_stake.earned_reward = user_stake.earned_reward + (earned as u64);

        // update unobtainable_reward for specific epoch
        let unobtainable_reward = vector::borrow_mut(&mut user_stake.unobtainable_rewards, epoch);
        *unobtainable_reward = *unobtainable_reward + earned;
    }

    /// Calculates user earnings without stake update.
    ///     * `accum_reward` - reward accumulated by pool.
    ///     * `scale` - multiplier to handle decimals.
    ///     * `user_stake` - stake to update earnings.
    /// Returns new stake earnings.
    fun user_lb_earned_since_last_update(
        accum_reward: u128,
        scale: u128,
        user_stake: &mut UserLbStake,
        epoch: u64,
    ): u128 {
        // create a slot for unobtainable reward if needed
        let unobtainable_reward = if (vector::length(&user_stake.unobtainable_rewards) < epoch + 1) {
            vector::push_back(&mut user_stake.unobtainable_rewards, 0);
            0
        } else {
            *vector::borrow(&user_stake.unobtainable_rewards, epoch)
        };

        ((accum_reward * user_stake_amount_with_boosted(user_stake)) / scale)
            - unobtainable_reward
    }

    /// Getting the Bin id for the LB token
    ///     * `token_id` - he TokenId of the LB token
    fun get_bin_id(token_id: TokenId): u64 {
        let properties = token::get_property_map(@liquidswap_v1_resource_account, token_id);
        property_map::read_u64(&properties, &string::utf8(b"Bin ID"))
    }

    /// Calculates pool accumulated reward, updating pool.
    ///     * `pool` - pool to update rewards.
    fun update_lb_accum_reward<R>(pool: &mut StakeLbPool<R>) {
        let epoch = vector::borrow_mut(&mut pool.epochs, pool.current_epoch);
        let current_time = timestamp::now_seconds();

        if (epoch.reward_per_sec == 0) {
            // handle ghost epoch
            epoch.last_update_time = current_time;
            epoch.end_time = current_time;
        } else {
            // handle reward epoch
            let epoch_end_time = epoch.end_time;
            let reward_time = math64::min(epoch_end_time, current_time);

            // let pool_total_staked_with_boosted = pool_total_staked_with_boosted(&pool.stake_tokens, pool.total_boosted);
            let pool_total_staked_with_boosted = pool.amounts + pool.total_boosted;
            let new_accum_rewards =
                accum_rewards_since_last_updated(
                    pool_total_staked_with_boosted,
                    epoch.last_update_time,
                    epoch.reward_per_sec,
                    reward_time,
                    pool.scale
                );
            if (new_accum_rewards != 0) {
                epoch.accum_reward = epoch.accum_reward + new_accum_rewards;
            };

            epoch.last_update_time = current_time;

            // calculate distributed rewards amount
            let undistrib_rewards_amount = 0;
            if (epoch_end_time > current_time) {
                let epoch_time_left = epoch_end_time - current_time;
                undistrib_rewards_amount = epoch_time_left * epoch.reward_per_sec
            };
            epoch.distributed = epoch.rewards_amount - undistrib_rewards_amount;

            // create ghost epoch to fill up empty period
            if (epoch_end_time <= current_time) {
                epoch.ended_at = current_time;
                let ghost_epoch = Epoch<R> {
                    rewards_amount: 0,
                    reward_per_sec: 0,
                    accum_reward: 0,
                    start_time: epoch_end_time,
                    last_update_time: current_time,
                    end_time: current_time + WEEK_IN_SECONDS,
                    distributed: 0,
                    ended_at: 0,
                    is_ghost: true
                };
                vector::push_back(&mut pool.epochs, ghost_epoch);

                pool.current_epoch = pool.current_epoch + 1;
            };
        };
    }

    /// The function of getting the creator, the name of the collection and the name of the token from the token.
    ///     * `token` - token from which need to get the necessary information.
    /// Returns creator, collection name and name.
    fun get_token_fields(token: &Token): (address, String, String) {
        let token_id = token::get_token_id(token);
        let token_data_id = token::get_tokendata_id(token_id);
        token::get_token_data_id_fields(&token_data_id)
    }

    /// Checks if local pool or global emergency enabled.
    ///     * `pool` - pool to check emergency.
    /// Returns true of any kind or both of emergency enabled.
    fun is_emergency_inner<S, R>(pool: &StakePool<S, R>): bool {
        pool.emergency_locked || stake_config::is_global_emergency()
    }

    /// Calculates pool accumulated reward, updating pool.
    ///     * `pool` - pool to update rewards.
    fun update_accum_reward<S, R>(pool: &mut StakePool<S, R>) {
        // we have 4 options here:
        // 1. Current epoch with no time passed
        //      ==> rewards 0
        // 2. Current epoch with some time passed
        //      ==> calc rewards
        // 3. Current epoch with exact duration passed
        //      ==> calc rewards

        // 4. Current epoch unfinished and not actual (create empty)
        //      ==> rewards, finish, create empty
        // 5. We are somewhere at ghost epoch
        //      ==> rewards 0

        let epoch = vector::borrow_mut(&mut pool.epochs, pool.current_epoch);
        let current_time = timestamp::now_seconds();

        if (epoch.reward_per_sec == 0) {
            // handle ghost epoch
            epoch.last_update_time = current_time;
            epoch.end_time = current_time;
        } else {
            // handle reward epoch
            let epoch_end_time = epoch.end_time;
            let reward_time = math64::min(epoch_end_time, current_time);

            let pool_total_staked_with_boosted =
                (coin::value(&pool.stake_coins) as u128) + pool.total_boosted;
            let new_accum_rewards =
                accum_rewards_since_last_updated(
                    pool_total_staked_with_boosted,
                    epoch.last_update_time,
                    epoch.reward_per_sec,
                    reward_time,
                    pool.scale
                );
            if (new_accum_rewards != 0) {
                epoch.accum_reward = epoch.accum_reward + new_accum_rewards;
            };

            epoch.last_update_time = current_time;

            // calculate distributed rewards amount
            let undistrib_rewards_amount = 0;
            if (epoch_end_time > current_time) {
                let epoch_time_left = epoch_end_time - current_time;
                undistrib_rewards_amount = epoch_time_left * epoch.reward_per_sec
            };
            epoch.distributed = epoch.rewards_amount - undistrib_rewards_amount;

            // create ghost epoch to fill up empty period
            if (epoch_end_time <= current_time) {
                epoch.ended_at = current_time;
                let ghost_epoch = Epoch<R> {
                    rewards_amount: 0,

                    reward_per_sec: 0,
                    accum_reward: 0,

                    start_time: epoch_end_time,
                    last_update_time: current_time,
                    end_time: current_time + WEEK_IN_SECONDS,

                    distributed: 0,
                    ended_at: 0,

                    is_ghost: true
                };
                vector::push_back(&mut pool.epochs, ghost_epoch);

                pool.current_epoch = pool.current_epoch + 1;
            };
        };
    }

    /// Calculates accumulated reward without pool update.
    ///     * `total_boosted_stake` - total amount of staked coins with boosts.
    ///     * `last_update_time` - last update time of epoch `accum_reward` field.
    ///     * `reward_per_sec` - rewards to distribute per second of epoch duration.
    ///     * `reward_time` - time passed since last update or epoch end time.
    ///     * `scale` - multiplier to handle decimals.
    /// Returns new accumulated reward.
    fun accum_rewards_since_last_updated(
        total_boosted_stake: u128,
        last_update_time: u64,
        reward_per_sec: u64,
        reward_time: u64,
        scale: u128,
    ): u128 {
        let seconds_passed = reward_time - last_update_time;
        if (seconds_passed == 0) return 0;

        if (total_boosted_stake == 0) return 0;

        let total_rewards =
            (reward_per_sec as u128) * (seconds_passed as u128) * scale;
        total_rewards / total_boosted_stake
    }

    /// Updates user earnings.
    ///     * `pool` - pool to get epochs and stakes.
    ///     * `user_address` - address of user to update earnings for.
    fun update_earnings_epochs<S, R>(pool: &mut StakePool<S, R>, user_address: address) {
        let epoch_count = pool.current_epoch + 1;
        let epochs = &mut pool.epochs;
        let user_stake = table::borrow_mut(&mut pool.stakes, user_address);

        let i = 0;
        while (i < epoch_count) {
            let epoch = vector::borrow_mut(epochs, i);

            update_user_earnings(epoch.accum_reward, pool.scale, user_stake, i);
            i = i + 1;
        };
    }

    /// Calculates user earnings, updating user stake.
    ///     * `accum_reward` - reward accumulated by pool.
    ///     * `scale` - multiplier to handle decimals.
    ///     * `user_stake` - stake to update earnings.
    fun update_user_earnings(accum_reward: u128, scale: u128, user_stake: &mut UserStake, epoch: u64) {
        let earned =
            user_earned_since_last_update(accum_reward, scale, user_stake, epoch);
        user_stake.earned_reward = user_stake.earned_reward + (earned as u64);

        // update unobtainable_reward for specific epoch
        let unobtainable_reward = vector::borrow_mut(&mut user_stake.unobtainable_rewards, epoch);
        *unobtainable_reward = *unobtainable_reward + earned;
    }

    /// Calculates user earnings without stake update.
    ///     * `accum_reward` - reward accumulated by pool.
    ///     * `scale` - multiplier to handle decimals.
    ///     * `user_stake` - stake to update earnings.
    /// Returns new stake earnings.
    fun user_earned_since_last_update(
        accum_reward: u128,
        scale: u128,
        user_stake: &mut UserStake,
        epoch: u64,
    ): u128 {
        // create a slot for unobtainable reward if needed
        let unobtainable_reward = if (vector::length(&user_stake.unobtainable_rewards) < epoch + 1) {
            vector::push_back(&mut user_stake.unobtainable_rewards, 0);
            0
        } else {
            *vector::borrow(&user_stake.unobtainable_rewards, epoch)
        };

        ((accum_reward * user_stake_amount_with_boosted(user_stake)) / scale)
            - unobtainable_reward
    }

    /// Calculates unobtainable reward for user.
    ///     * `scale` - multiplier to handle decimals.
    ///     * `epoch_count` - count of epochs in pool.
    ///     * `epochs` - vector of pool epochs.
    ///     * `user_stake` - the user stake.
    fun update_unobtainable_reward<R>(
        scale: u128,
        epoch_count: u64,
        epochs: &vector<Epoch<R>>,
        user_stake: &mut UserStake
    ) {
        let i = 0;
        while (i < epoch_count) {
            let accum_reward = vector::borrow(epochs, i).accum_reward;
            let unobt_rew = (accum_reward * user_stake_amount_with_boosted(user_stake)) / scale;

            let el = vector::borrow_mut(&mut user_stake.unobtainable_rewards, i);
            *el = unobt_rew;

            i = i + 1;
        };
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
        new_amount: u64,
        prev_amount: u64,
        epoch_duration: u64,
    }

    struct HarvestEvent has drop, store {
        user_address: address,
        amount: u64,
    }

    #[test_only]
    /// Access unobtainable_reward field in user stake.
    public fun get_unobtainable_reward<S, R>(
        pool_addr: address,
        user_addr: address,
    ): u128 acquires StakePool {
        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        let user_stake = table::borrow(&pool.stakes, user_addr);

        let total_unobt_rew = 0;
        let unobt_len = vector::length(&user_stake.unobtainable_rewards);
        let epoch_count = pool.current_epoch + 1;
        let i = 0;
        while (i < epoch_count) {
            let unobt_rew = 0;
            if (i < unobt_len) {
                unobt_rew = *vector::borrow(&user_stake.unobtainable_rewards, i);
            };

            total_unobt_rew = total_unobt_rew + unobt_rew;
            i = i + 1;
        };

        total_unobt_rew
    }

    #[test_only]
    /// Access staking pool fields with no getters.
    public fun get_pool_info<S, R>(pool_addr: address): (u64, u128, u64, u64, u128) acquires StakePool {
        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        let epoch = vector::borrow(&pool.epochs, pool.current_epoch);

        (epoch.reward_per_sec, epoch.accum_reward, epoch.last_update_time,
            coin::value<R>(&pool.reward_coins), pool.scale)
    }

    #[test_only]
    /// Access staking pool fields with no getters.
    public fun get_epoch_info<S, R>(pool_addr: address, epoch: u64):
        (u64, u64, u128, u64, u64, u64, u64, u64, bool) acquires StakePool {
        let pool = borrow_global<StakePool<S, R>>(pool_addr);
        let epoch = vector::borrow(&pool.epochs, epoch);

        (epoch.rewards_amount, epoch.reward_per_sec, epoch.accum_reward, epoch.start_time,
            epoch.last_update_time, epoch.end_time, epoch.distributed, epoch.ended_at, epoch.is_ghost)
    }

    #[test_only]
    /// Force pool & user stake recalculations.
    public fun recalculate_user_stake<S, R>(pool_addr: address, user_addr: address) acquires StakePool {
        let pool = borrow_global_mut<StakePool<S, R>>(pool_addr);

        update_accum_reward(pool);
        update_earnings_epochs(pool, user_addr);
    }
}
