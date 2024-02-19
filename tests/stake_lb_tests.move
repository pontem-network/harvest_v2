#[test_only]
module harvest::stake_lb_tests {
    use std::option;
    use std::signer;
    use std::string;

    use aptos_framework::coin;
    use aptos_framework::genesis;
    use aptos_framework::timestamp;

    use aptos_token::token;

    use harvest::stake_lb::is_finished;
    use harvest::stake_lb;
    use harvest::stake_config;
    use harvest::stake_test_helpers::{
        new_account,
        initialize_reward_coin,
        mint_default_coin,
        RewardCoin,
        create_st_collection,
        create_stake_token,
        StakeCoin,
        initialize_stake_coin,
        new_account_with_stake_coins, mint_token
    };

    // week in seconds, lockup period
    const WEEK_IN_SECONDS: u64 = 604800;

    const START_TIME: u64 = 682981200;

    public fun initialize_test(): (signer, signer, signer) {
        genesis::setup();

        timestamp::update_global_time_for_test_secs(START_TIME);

        let harvest = new_account(@harvest);
        let collection_owner = new_account(@liquidswap_v1_resource_account);

        // create coins for pool to be valid
        initialize_reward_coin(&harvest, 6);
        initialize_stake_coin(&harvest, 6);

        let emergency_admin = new_account(@stake_emergency_admin);
        stake_config::initialize(&emergency_admin, @treasury);
        (harvest, emergency_admin, collection_owner)
    }

    #[test]
    public fun test_register() {
        let (_, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&alice_acc, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&alice_acc, stake_token);
        // check pool statistics
        let (reward_per_sec, accum_reward, last_updated, reward_amount, scale) =
            stake_lb::get_pool_info<RewardCoin>(@alice, collection_name);
        let end_ts = stake_lb::get_end_timestamp<RewardCoin>(@alice, collection_name);
        assert!(end_ts == START_TIME + duration, 1);
        assert!(reward_per_sec == 1000000, 1);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME, 1);
        assert!(reward_amount == 15768000000000, 1);
        assert!(scale == 1000000, 1);
        assert!(stake_lb::pool_exists<RewardCoin>(@alice, collection_name), 1);
        assert!(
            stake_lb::get_pool_total_stake<RewardCoin>(@alice, collection_name) == 0,
            1
        ); // Check amount stake token for register
    }

    #[test]
    public fun test_register_two_pools() {
        let (_, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let bob_acc = new_account(@bob);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&alice_acc, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&alice_acc, stake_token);

        // register staking pool 2 with rewards
        let collection_name_two = string::utf8(b"Liquidswap v1 #1 \"BTC\"-\"USDC\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name_two);
        let stake_token_two = create_stake_token(&collection_owner, collection_name_two, string::utf8(b"LB2"));
        let reward_coins = mint_default_coin<StakeCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<StakeCoin>(&bob_acc, &stake_token_two, reward_coins, duration, option::none());
        token::deposit_token(&bob_acc, stake_token_two);

        // check pools exist
        assert!(stake_lb::pool_exists<RewardCoin>(@alice, collection_name), 1);
        assert!(stake_lb::pool_exists<StakeCoin>(@bob, collection_name_two), 1);
    }

    #[test]
    public fun test_deposit_reward_coins() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&alice_acc, stake_token);

        // check pool statistics
        let pool_finish_time = START_TIME + duration;
        let (reward_per_sec, _, _, reward_amount, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        let end_ts = stake_lb::get_end_timestamp<RewardCoin>(@harvest, collection_name);
        assert!(end_ts == pool_finish_time, 1);
        assert!(reward_per_sec == 1000000, 1);
        assert!(reward_amount == 15768000000000, 1);

        // deposit more rewards
        let reward_coins = mint_default_coin<RewardCoin>(604800000000);
        stake_lb::deposit_reward_coins<RewardCoin>(&alice_acc, @harvest, collection_name, reward_coins);

        // check pool statistics
        let pool_finish_time = pool_finish_time + 604800;
        let (reward_per_sec, _, _, reward_amount, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        let end_ts = stake_lb::get_end_timestamp<RewardCoin>(@harvest, collection_name);
        assert!(end_ts == pool_finish_time, 1);
        assert!(reward_per_sec == 1000000, 1);
        assert!(reward_amount == 16372800000000, 1);

        // wait to a second before pool duration end
        timestamp::update_global_time_for_test_secs(pool_finish_time - 1);

        // deposit more rewards
        let reward_coins = mint_default_coin<RewardCoin>(604800000000);
        stake_lb::deposit_reward_coins<RewardCoin>(&harvest, @harvest, collection_name, reward_coins);

        // check pool statistics
        let pool_finish_time = pool_finish_time + 604800;
        let (reward_per_sec, _, _, reward_amount, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        let end_ts = stake_lb::get_end_timestamp<RewardCoin>(@harvest, collection_name);

        assert!(end_ts == pool_finish_time, 1);
        assert!(reward_per_sec == 1000000, 1);
        assert!(reward_amount == 16977600000000, 1);
    }

    #[test]
    public fun test_stake_and_unstake() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let bob_acc = new_account(@bob);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 1299000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 900000000);
        token::direct_transfer(&collection_owner, &bob_acc, token_id, 99000000);

        // check no stakes
        assert!(!stake_lb::stake_exists<RewardCoin>(@harvest, collection_name, @alice), 1);
        assert!(!stake_lb::stake_exists<RewardCoin>(@harvest, collection_name, @bob), 1);

        // stake 500 StakeCoins from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 500000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 500000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        assert!(token::balance_of(@alice, token_id) == 400000000, 1);
        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, collection_name, @alice) == 500000000, 1);
        assert!(stake_lb::get_pool_total_stake<RewardCoin>(@harvest, collection_name) == 500000000, 1);

        // stake 99 StakeCoins from bob
        let split_token = token::withdraw_token(&bob_acc, token_id, 99000000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, split_token);

        assert!(token::balance_of(@bob, token_id) == 0, 1);

        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, collection_name, @bob) == 99000000, 1);
        assert!(stake_lb::get_pool_total_stake<RewardCoin>(@harvest, collection_name) == 599000000, 1);

        // stake 300 StakeCoins more from alice
        let split_token = token::withdraw_token(&alice_acc, token_id, 300000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        assert!(token::balance_of(@alice, token_id) == 100000000, 1);

        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, collection_name, @alice) == 800000000, 1);
        assert!(stake_lb::get_pool_total_stake<RewardCoin>(@harvest, collection_name) == 899000000, 1);

        // wait one week to unstake
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        // unstake 400 StakeCoins from alice
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 400000000);

        assert!(token::get_token_amount(&token) == 400000000, 1);
        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, collection_name, @alice) == 400000000, 1);
        assert!(stake_lb::get_pool_total_stake<RewardCoin>(@harvest, collection_name) == 499000000, 1);
        token::deposit_token(&alice_acc, token);

        // unstake all 99 StakeCoins from bob
        let token =
            stake_lb::unstake<RewardCoin>(&bob_acc, @harvest, collection_name, 99000000);
        assert!(token::get_token_amount(&token) == 99000000, 1);
        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, collection_name, @bob) == 0, 1);
        assert!(stake_lb::get_pool_total_stake<RewardCoin>(@harvest, collection_name) == 400000000, 1);
        token::deposit_token(&bob_acc, token);
        token::deposit_token(&bob_acc, stake_token);
    }

    #[test]
    public fun test_unstake_works_after_pool_duration_end() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 12346);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 12345);

        // stake from alice
        let split_token = token::withdraw_token(&alice_acc, token_id, 12345);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // wait until pool expired and a week more
        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS);

        // unstake from alice
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 12345);

        assert!(token::get_token_amount(&token) == 12345, 1);
        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);
        assert!(stake_lb::get_pool_total_stake<RewardCoin>(@harvest, collection_name) == 0, 1);
        token::deposit_token(&alice_acc, token);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_stake_lockup_period() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let bob_acc = new_account(@bob);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // distribution of tokens for later use
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 1750000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 1000000);
        token::direct_transfer(&collection_owner, &bob_acc, token_id, 750000);

        // stake from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 500000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 500000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // check alice stake unlock time
        let unlock_time = stake_lb::get_unlock_time<RewardCoin>(@harvest, collection_name, @alice);
        assert!(unlock_time == START_TIME + WEEK_IN_SECONDS, 1);

        // wait 100 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 100);

        // stake from bob
        // let coins =
        //     coin::withdraw<StakeCoin>(&bob_acc, 500000);
        let split_token = token::withdraw_token(&bob_acc, token_id, 500000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, split_token);

        // check bob stake unlock time
        let unlock_time = stake_lb::get_unlock_time<RewardCoin>(@harvest, collection_name, @bob);
        assert!(unlock_time == START_TIME + WEEK_IN_SECONDS + 100, 1);

        // stake more from alice before lockup period end
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 500000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 500000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // check alice stake unlock time updated
        let unlock_time = stake_lb::get_unlock_time<RewardCoin>(@harvest, collection_name, @alice);
        assert!(unlock_time == START_TIME + WEEK_IN_SECONDS + 100, 1);

        // wait one week
        timestamp::update_global_time_for_test_secs(START_TIME + 100 + WEEK_IN_SECONDS);

        // unstake from alice after lockup period end
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 1000000);
        token::deposit_token(&alice_acc, token);

        // wait 100 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 200 + WEEK_IN_SECONDS);

        // partial unstake from bob after lockup period end
        let token =
            stake_lb::unstake<RewardCoin>(&bob_acc, @harvest, collection_name, 250000);
        token::deposit_token(&bob_acc, token);

        // wait 100 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 300 + WEEK_IN_SECONDS);

        // stake more from bob after lockup period end
        let token =
            token::withdraw_token(&bob_acc, token_id, 500000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, token);

        // check bob stake unlock time updated
        let unlock_time = stake_lb::get_unlock_time<RewardCoin>(@harvest, collection_name, @bob);
        assert!(unlock_time == START_TIME + WEEK_IN_SECONDS + 300 + WEEK_IN_SECONDS, 1);

        // wait 1 year
        timestamp::update_global_time_for_test_secs(START_TIME + 31536000);

        // unstake from bob almost year after lockup period end
        let token =
            stake_lb::unstake<RewardCoin>(&bob_acc, @harvest, collection_name, 250000);
        token::deposit_token(&bob_acc, token);
        token::deposit_token(&bob_acc, stake_token);
    }

    #[test]
    public fun test_get_start_timestamp() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(604805000000);
        let duration = 604805;
        let start_ts = timestamp::now_seconds();
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&alice_acc, stake_token);

        assert!(stake_lb::get_start_timestamp<RewardCoin>(@harvest, collection_name) == start_ts, 1);

        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);
        assert!(stake_lb::get_start_timestamp<RewardCoin>(@harvest, collection_name) == start_ts, 1);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_POOLS)]
    public fun test_get_start_timestamp_fails_no_pool_exists() {
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");

        let _ = stake_lb::get_start_timestamp<RewardCoin>(@harvest, collection_name);
    }

    #[test]
    public fun test_is_unlocked() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let bob_acc = new_account(@bob);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(604805000000);
        let duration = 604805;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 1000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 500000);
        token::direct_transfer(&collection_owner, &bob_acc, token_id, 500000);

        // stake from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 500000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 500000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        assert!(!stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @alice), 1);

        // wait almost a week
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS - 1);

        assert!(!stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @alice), 1);

        // stake from bob
        // let coins =
        //     coin::withdraw<StakeCoin>(&bob_acc, 500000);
        let split_token = token::withdraw_token(&bob_acc, token_id, 500000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, split_token);

        assert!(!stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @bob), 1);

        // wait a second
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        assert!(stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @alice), 1);
        assert!(!stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @bob), 1);

        // wait until pool expired
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        assert!(stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @alice), 1);
        assert!(stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @bob), 1);

        // wait a week more
        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS);

        assert!(stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @alice), 1);
        assert!(stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @bob), 1);
        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    public fun test_is_unlocked_early() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(604805000000);
        let duration = 3600;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 500000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 500000);

        // stake from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 500000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 500000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        assert!(!stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @alice), 1);

        // wait almost a hour
        timestamp::update_global_time_for_test_secs(START_TIME + 3600 - 1);
        assert!(!stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @alice), 1);

        // wait a hour
        timestamp::update_global_time_for_test_secs(START_TIME + 3600);
        assert!(stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @alice), 1);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_get_unlock_time_early() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(604805000000);
        let duration = 3600;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 500000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 500000);

        // stake from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 500000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 500000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        assert!(stake_lb::get_unlock_time<RewardCoin>(@harvest, collection_name, @alice) == START_TIME + 3600, 1);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_reward_calculation() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 900000000);
        let bob_acc = new_account_with_stake_coins(@bob, 99000000);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 1890000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 900000000);
        token::direct_transfer(&collection_owner, &bob_acc, token_id, 99000000);

        // stake 100 StakeCoins from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // check stake parameters
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @alice);
        assert!(unobtainable_reward == 0, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 10);

        // synthetic recalculate
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @alice);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        // (reward_per_sec_rate * time passed / total_staked) + previous period
        assert!(accum_reward == 1000000, 1);
        assert!(last_updated == START_TIME + 10, 1);

        // check alice's stake
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @alice);
        assert!(unobtainable_reward == 100000000, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 100000000, 1);

        // stake 50 StakeCoins from bob
        // let coins =
        //     coin::withdraw<StakeCoin>(&bob_acc, 50000000);
        let split_token = token::withdraw_token(&bob_acc, token_id, 50000000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, split_token);

        // check bob's stake parameters
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @bob);
        // stake amount * pool accum_reward
        // accumulated benefit that does not belong to bob
        assert!(unobtainable_reward == 50000000, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @bob) == 0, 1);

        // stake 100 StakeCoins more from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 20);

        // synthetic recalculate
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @alice);
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @bob);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        assert!(accum_reward == 1400000, 1);
        assert!(last_updated == START_TIME + 20, 1);

        // check alice's stake parameters
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @alice);
        assert!(unobtainable_reward == 280000000, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 180000000, 1);

        // check bob's stake parameters
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @bob);
        assert!(unobtainable_reward == 70000000, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @bob) == 20000000, 1);

        // wait one week to unstake
        timestamp::update_global_time_for_test_secs(START_TIME + 20 + WEEK_IN_SECONDS);

        // synthetic recalculate
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @alice);
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @bob);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        assert!(accum_reward == 24193400000, 1);
        assert!(last_updated == START_TIME + 20 + WEEK_IN_SECONDS, 1);

        // check alice's stake parameters
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @alice);
        assert!(unobtainable_reward == 4838680000000, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 4838580000000, 1);

        // check bob's stake parameters
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @bob);
        assert!(unobtainable_reward == 1209670000000, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @bob) == 1209620000000, 1);

        // unstake 100 StakeCoins from alice
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 100000000);
        token::deposit_token(&alice_acc, token);

        // check alice's stake parameters
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @alice);
        assert!(unobtainable_reward == 2419340000000, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 4838580000000, 1);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 30 + WEEK_IN_SECONDS);

        // synthetic recalculate
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @alice);
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @bob);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        assert!(accum_reward == 24194066666, 1);
        assert!(last_updated == START_TIME + 30 + WEEK_IN_SECONDS, 1);

        // check alice's stake parameters
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @alice);
        let earned_reward1 = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice);
        assert!(unobtainable_reward == 2419406666600, 1);
        assert!(earned_reward1 == 4838646666600, 1);

        // check bob's stake parameters
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @bob);
        let earned_reward2 = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @bob);
        assert!(unobtainable_reward == 1209703333300, 1);
        assert!(earned_reward2 == 1209653333300, 1);

        // 0.000001 RewardCoin lost during calculations
        let total_rewards = (30 + WEEK_IN_SECONDS) * 10000000;
        let total_earned = earned_reward1 + earned_reward2;
        let losed_rewards = total_rewards - total_earned;

        assert!(losed_rewards == 100, 1);
        token::deposit_token(&bob_acc, stake_token);
    }

    #[test]
    public fun test_reward_calculation_works_well_when_pool_is_empty() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 100000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);

        // wait one week with empty pool
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME, 1);

        // stake from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // check stake parameters
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @alice);
        assert!(unobtainable_reward == 0, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME + WEEK_IN_SECONDS, 1);

        // wait one week with stake
        timestamp::update_global_time_for_test_secs(START_TIME + (WEEK_IN_SECONDS * 2));

        // synthetic recalculate
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @alice);

        // check stake parameters, here we count on that user receives reward for one week only
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @alice);
        // 604800 seconds * 10 rew_per_second, all coins belong to user
        assert!(unobtainable_reward == 6048000000000, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 6048000000000, 1);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        // 604800 seconds * 10 rew_per_second / 100 total_staked
        assert!(accum_reward == 60480000000, 1);
        assert!(last_updated == START_TIME + (WEEK_IN_SECONDS * 2), 1);

        // unstake from alice
        let token
            = stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 100000000);
        token::deposit_token(&alice_acc, token);

        // check stake parameters
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @alice);
        // 604800 seconds * 10 rew_per_second, all coins belong to user
        assert!(unobtainable_reward == 0, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 6048000000000, 1);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        // 604800 seconds * 10 rew_per_second / 100 total_staked
        assert!(accum_reward == 60480000000, 1);
        assert!(last_updated == START_TIME + (WEEK_IN_SECONDS * 2), 1);

        // wait few more weeks with empty pool
        timestamp::update_global_time_for_test_secs(START_TIME + (WEEK_IN_SECONDS * 5));

        // stake again from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // check stake parameters, user should not be able to claim rewards for period after unstake
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @alice);
        assert!(unobtainable_reward == 6048000000000, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 6048000000000, 1);

        // check pool parameters, pool should not accumulate rewards when no stakes in it
        let (_, accum_reward, last_updated, _, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        assert!(accum_reward == 60480000000, 1);
        assert!(last_updated == START_TIME + (WEEK_IN_SECONDS * 5), 1);

        // wait one week after stake
        timestamp::update_global_time_for_test_secs(START_TIME + (WEEK_IN_SECONDS * 6));

        // synthetic recalculate
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @alice);

        // check stake parameters, user should not be able to claim rewards for period after unstake
        let unobtainable_reward =
            stake_lb::get_unobtainable_reward<RewardCoin>(@harvest, collection_name, @alice);
        assert!(unobtainable_reward == 12096000000000, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 12096000000000, 1);

        // check pool parameters, pool should not accumulate rewards when no stakes in it
        let (_, accum_reward, last_updated, _, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        assert!(accum_reward == 120960000000, 1);
        assert!(last_updated == START_TIME + (WEEK_IN_SECONDS * 6), 1);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_harvest() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let bob_acc = new_account(@bob);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 200000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);
        token::direct_transfer(&collection_owner, &bob_acc, token_id, 100000000);

        // stake 100 StakeCoins from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 10);

        // harvest from alice
        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);

        // check amounts
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);
        assert!(coin::value(&coins) == 100000000, 1);

        coin::deposit<RewardCoin>(@alice, coins);

        // stake 100 StakeCoins from bob
        // let coins =
        //     coin::withdraw<StakeCoin>(&bob_acc, 100000000);
        let split_token = token::withdraw_token(&bob_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, split_token);

        // wait one week to unstake
        timestamp::update_global_time_for_test_secs(START_TIME + 10 + WEEK_IN_SECONDS);

        // harvest from alice
        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);

        // check amounts
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);
        assert!(coin::value(&coins) == 3024000000000, 1);

        coin::deposit<RewardCoin>(@alice, coins);

        // harvest from bob
        let coins =
            stake_lb::harvest<RewardCoin>(&bob_acc, @harvest, collection_name);

        // check amounts
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @bob) == 0, 1);
        assert!(coin::value(&coins) == 3024000000000, 1);

        coin::deposit<RewardCoin>(@bob, coins);

        // unstake 100 StakeCoins from alice
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 100000000);
        token::deposit_token(&bob_acc, token);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 20 + WEEK_IN_SECONDS);

        // harvest from bob
        let coins =
            stake_lb::harvest<RewardCoin>(&bob_acc, @harvest, collection_name);

        // check amounts
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @bob) == 0, 1);
        assert!(coin::value(&coins) == 100000000, 1);

        coin::deposit<RewardCoin>(@bob, coins);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_harvest_works_after_pool_duration_end() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 100000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);

        // stake 100 StakeCoins from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // wait until pool expired and a week more
        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS);

        // harvest from alice
        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);

        // check amounts
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);
        assert!(coin::value(&coins) == 157680000000000, 1);

        coin::deposit<RewardCoin>(@alice, coins);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_stake_and_harvest_for_pool_less_than_week_duration() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let bob_acc = new_account(@bob);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);

        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(302400000000);
        let duration = 302400;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 130000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);
        token::direct_transfer(&collection_owner, &bob_acc, token_id, 30000000);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // let coins =
        //     coin::withdraw<StakeCoin>(&bob_acc, 30000000);
        let split_token = token::withdraw_token(&bob_acc, token_id, 30000000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, split_token);

        timestamp::update_global_time_for_test_secs(START_TIME + duration + 1);

        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);

        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);
        assert!(coin::value(&coins) == 232615384600, 1);

        coin::deposit<RewardCoin>(@alice, coins);

        let coins =
            stake_lb::harvest<RewardCoin>(&bob_acc, @harvest, collection_name);

        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @bob) == 0, 1);
        assert!(coin::value(&coins) == 69784615380, 1);

        coin::deposit<RewardCoin>(@bob, coins);

        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 100000000);
        token::deposit_token(&alice_acc, token);

        let token =
            stake_lb::unstake<RewardCoin>(&bob_acc, @harvest, collection_name, 30000000);
        token::deposit_token(&bob_acc, token);

        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @bob) == 0, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_stake_and_harvest_big_real_values() {
        // well, really i just want to test large numbers with 8 decimals, so this why we have billions.
        let (harvest, _, collection_owner) = initialize_test();

        // 900b of coins.
        let alice_acc = new_account(@alice);
        // 100b of coins.
        let bob_acc = new_account(@bob);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);

        // 1000b of coins
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(1000000000000000000);
        // 1 week.
        let duration = WEEK_IN_SECONDS;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 1000000000000000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 900000000000000000);
        token::direct_transfer(&collection_owner, &bob_acc, token_id, 100000000000000000);

        // stake alice.
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 90000000000000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 90000000000000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // stake bob.
        // let coins =
        //     coin::withdraw<StakeCoin>(&bob_acc, 10000000000000000);
        let split_token = token::withdraw_token(&bob_acc, token_id, 10000000000000000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, split_token);

        timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);

        // harvest first time.
        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);
        coin::deposit<RewardCoin>(@alice, coins);
        let coins =
            stake_lb::harvest<RewardCoin>(&bob_acc, @harvest, collection_name);
        coin::deposit<RewardCoin>(@bob, coins);

        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // harvest second time.
        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);
        coin::deposit<RewardCoin>(@alice, coins);
        let coins =
            stake_lb::harvest<RewardCoin>(&bob_acc, @harvest, collection_name);
        coin::deposit<RewardCoin>(@bob, coins);

        // unstake.
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 90000000000000000);
        token::deposit_token(&alice_acc, token);

        let token =
            stake_lb::unstake<RewardCoin>(&bob_acc, @harvest, collection_name, 10000000000000000);
        token::deposit_token(&bob_acc, token);
        token::deposit_token(&bob_acc, stake_token);
    }

    #[test]
    public fun test_stake_and_harvest_big_real_values_long_time() {
        // well, really i just want to test large numbers with 8 decimals, so this why we have billions.
        let (harvest, _, collection_owner) = initialize_test();

        // 900b of coins.
        let alice_acc = new_account(@alice);
        // 100b of coins.
        let bob_acc = new_account(@bob);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);

        // 1000b of coins
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(1000000000000000000);
        // 10 years.
        let duration = 31536000 * 10;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 1000000000000000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 900000000000000000);
        token::direct_transfer(&collection_owner, &bob_acc, token_id, 100000000000000000);

        // stake alice.
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 90000000000000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 90000000000000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // stake bob.
        // let coins =
        //     coin::withdraw<StakeCoin>(&bob_acc, 10000000000000000);
        let split_token = token::withdraw_token(&bob_acc, token_id, 10000000000000000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, split_token);

        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);
        coin::deposit<RewardCoin>(@alice, coins);
        let coins =
            stake_lb::harvest<RewardCoin>(&bob_acc, @harvest, collection_name);
        coin::deposit<RewardCoin>(@bob, coins);

        // unstake.
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 90000000000000000);
        token::deposit_token(&alice_acc, token);

        let token =
            stake_lb::unstake<RewardCoin>(&bob_acc, @harvest, collection_name, 10000000000000000);
        token::deposit_token(&bob_acc, token);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_premature_unstake_and_harvest() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 100000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);

        timestamp::update_global_time_for_test_secs(START_TIME + duration - 1);

        // stake 100 StakeCoins from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // wait until pool expired and almost a week more
        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS / 2);

        let token = stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 100000000);
        token::deposit_token(&alice_acc, token);

        // harvest from alice
        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);

        // check amounts
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);
        assert!(coin::value(&coins) == 10000000, 1);

        coin::deposit<RewardCoin>(@alice, coins);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_stake_and_get_all_rewards_from_start_to_end() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins_val = 157680000000000;
        let reward_coins = mint_default_coin<RewardCoin>(reward_coins_val);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 100000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);

        // stake 100 StakeCoins from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // wait until pool expired
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // harvest from alice
        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);

        // check amounts
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);
        assert!(coin::value(&coins) == reward_coins_val, 1);

        coin::deposit<RewardCoin>(@alice, coins);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_reward_is_not_accumulating_after_end() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);

        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // distribution of tokens for later use
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 100000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @alice);
        let (_, accum_reward, last_updated, _, _) = stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        let reward_val = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice);
        assert!(reward_val == 0, 1);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME, 1);

        timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @alice);
        let (_, accum_reward, last_updated, _, _) = stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        let reward_val = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice);
        assert!(reward_val == 78840000000000, 1);
        assert!(accum_reward == 788400000000, 1);
        assert!(last_updated == START_TIME + duration / 2, 1);

        timestamp::update_global_time_for_test_secs(START_TIME + duration);
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @alice);
        let (_, accum_reward, last_updated, _, _) = stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        let reward_val = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice);
        assert!(reward_val == 157680000000000, 1);
        assert!(accum_reward == 1576800000000, 1);
        assert!(last_updated == START_TIME + duration, 1);

        timestamp::update_global_time_for_test_secs(START_TIME + duration + 1);
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @alice);
        let (_, accum_reward, last_updated, _, _) = stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        let reward_val = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice);
        assert!(reward_val == 157680000000000, 1);
        assert!(accum_reward == 1576800000000, 1);
        assert!(last_updated == START_TIME + duration, 1);

        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS * 200);
        stake_lb::recalculate_user_stake<RewardCoin>(@harvest, collection_name, @alice);
        let (_, accum_reward, last_updated, _, _) = stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        let reward_val = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice);
        assert!(reward_val == 157680000000000, 1);
        assert!(accum_reward == 1576800000000, 1);
        assert!(last_updated == START_TIME + duration, 1);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_pool_exists() {
        let (harvest, _, collection_owner) = initialize_test();
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // check pool exists before register
        let exists = stake_lb::pool_exists<RewardCoin>(@harvest, collection_name);
        assert!(!exists, 1);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // check pool exists after register
        let exists = stake_lb::pool_exists<RewardCoin>(@harvest, collection_name);
        assert!(exists, 1);
        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    public fun test_stake_exists() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // distribution of tokens for later use
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 12345);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 12345);

        // check stake exists before alice stake
        let exists = stake_lb::stake_exists<RewardCoin>(@harvest, collection_name, @alice);
        assert!(!exists, 1);

        // stake from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 12345);
        let split_token = token::withdraw_token(&alice_acc, token_id, 12345);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // check stake exists after alice stake
        let exists = stake_lb::stake_exists<RewardCoin>(@harvest, collection_name, @alice);
        assert!(exists, 1);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_get_user_stake() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 100000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);

        // stake 50 StakeCoins from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 50000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 50000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);
        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, collection_name, @alice) == 50000000, 1);

        // stake 50 StakeCoins more from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 50000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 50000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);
        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, collection_name, @alice) == 100000000, 1);

        // wait one week to unstake
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        // unstake 30 StakeCoins from alice
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 30000000);
        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, collection_name, @alice) == 70000000, 1);
        token::deposit_token(&alice_acc, token);

        // unstake all from alice
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 70000000);
        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);
        token::deposit_token(&alice_acc, token);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_get_pending_user_rewards() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 100000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);

        // stake 100 StakeCoins from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // check stake earned and pool accum_reward
        let (_, accum_reward, _, _, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        assert!(accum_reward == 0, 1);
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);

        // wait one week
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        // check stake earned
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 604800000000, 1);

        // check get_pending_user_rewards calculations didn't affect pool accum_reward
        let (_, accum_reward, _, _, _) =
            stake_lb::get_pool_info<RewardCoin>(@harvest, collection_name);
        assert!(accum_reward == 0, 1);

        // unstake all 100 StakeCoins from alice
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 100000000);
        token::deposit_token(&alice_acc, token);

        // wait one week
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS + WEEK_IN_SECONDS);

        // check stake earned didn't change a week after full unstake
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 604800000000, 1);

        // harvest from alice
        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);
        assert!(coin::value(&coins) == 604800000000, 1);
        coin::deposit<RewardCoin>(@alice, coins);

        // check earned calculations after harvest
        assert!(stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice) == 0, 1);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_is_finished() {
        let (harvest, _, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // check is finished
        assert!(!is_finished<RewardCoin>(@harvest, collection_name), 1);

        // wait to a second before pool duration end
        timestamp::update_global_time_for_test_secs(START_TIME + duration - 1);

        // check is finished
        assert!(!is_finished<RewardCoin>(@harvest, collection_name), 1);

        // wait one second
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // check is finished
        assert!(is_finished<RewardCoin>(@harvest, collection_name), 1);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    public fun test_get_end_timestamp() {
        let (harvest, _, collection_owner) = initialize_test();
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // check pool expiration date
        let end_ts = stake_lb::get_end_timestamp<RewardCoin>(@harvest, collection_name);
        assert!(end_ts == START_TIME + duration, 1);

        // deposit more rewards
        let reward_coins = mint_default_coin<RewardCoin>(604800000000);
        stake_lb::deposit_reward_coins<RewardCoin>(&harvest, @harvest, collection_name, reward_coins);

        // check pool expiration date
        let end_ts = stake_lb::get_end_timestamp<RewardCoin>(@harvest, collection_name);
        assert!(end_ts == START_TIME + duration + 604800, 1);
        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_POOLS)]
    public fun test_deposit_reward_coins_fails_if_pool_does_not_exist() {
        let harvest = new_account(@harvest);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");

        // mint reward coins
        initialize_reward_coin(&harvest, 6);
        let reward_coins = mint_default_coin<RewardCoin>(100);

        stake_lb::deposit_reward_coins<RewardCoin>(&harvest, @harvest, collection_name, reward_coins);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_POOLS)]
    public fun test_stake_fails_if_pool_does_not_exist() {
        let harvest = new_account(@harvest);
        let collection_owner = new_account(@liquidswap_v1_resource_account);

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // mint stake coins
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));

        // stake when no pool
        stake_lb::stake<RewardCoin>(&harvest, @harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_POOLS)]
    public fun test_unstake_fails_if_pool_does_not_exist() {
        let harvest = new_account(@harvest);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");

        // unstake when no pool
        let token =
            stake_lb::unstake<RewardCoin>(&harvest, @harvest, collection_name, 12345);
        token::deposit_token(&harvest, token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_POOLS)]
    public fun test_harvest_fails_if_pool_does_not_exist() {
        let harvest = new_account(@harvest);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");

        // harvest when no pool
        let coins =
            stake_lb::harvest<RewardCoin>(&harvest, @harvest, collection_name);
        coin::deposit<RewardCoin>(@harvest, coins);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_POOLS)]
    public fun test_get_pool_total_staked_fails_if_pool_does_not_exist() {
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        stake_lb::get_pool_total_stake<RewardCoin>(@harvest, collection_name);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_POOLS)]
    public fun test_get_user_stake_fails_if_pool_does_not_exist() {
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        stake_lb::get_user_stake<RewardCoin>(@harvest, collection_name, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_POOLS)]
    public fun test_get_pending_user_rewards_fails_if_pool_does_not_exist() {
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_POOLS)]
    public fun test_get_unlock_time_fails_if_pool_does_not_exist() {
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        stake_lb::get_unlock_time<RewardCoin>(@harvest, collection_name, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_POOLS)]
    public fun test_is_unlocked_fails_if_pool_does_not_exist() {
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_POOLS)]
    public fun test_is_finished_fails_if_pool_does_not_exist() {
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        stake_lb::is_finished<RewardCoin>(@harvest, collection_name);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_POOLS)]
    public fun test_get_end_timestamp_fails_if_pool_does_not_exist() {
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        stake_lb::get_end_timestamp<RewardCoin>(@harvest, collection_name);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_POOL_ALREADY_EXISTS)]
    public fun test_register_fails_if_pool_already_exists() {
        initialize_test();
        let collection_owner = new_account(@liquidswap_v1_resource_account);
        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // get reward coins
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins_1 = mint_default_coin<RewardCoin>(12345);
        let reward_coins_2 = mint_default_coin<RewardCoin>(12345);

        // register staking pool twice
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&alice_acc, &stake_token, reward_coins_1, duration, option::none());
        stake_lb::register_pool<RewardCoin>(&alice_acc, &stake_token, reward_coins_2, duration, option::none());
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_REWARD_CANNOT_BE_ZERO)]
    public fun test_register_fails_if_reward_is_zero() {
        let (harvest, _, collection_owner) = initialize_test();
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = coin::zero<RewardCoin>();
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_STAKE)]
    public fun test_get_user_stake_fails_if_stake_does_not_exist() {
        let (harvest, _, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_lb::get_user_stake<RewardCoin>(@harvest, collection_name, @alice);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_STAKE)]
    public fun test_get_pending_user_rewards_fails_if_stake_does_not_exist() {
        let (harvest, _, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, collection_name, @alice);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_STAKE)]
    public fun test_get_unlock_time_fails_if_stake_does_not_exist() {
        let (harvest, _, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_lb::get_unlock_time<RewardCoin>(@harvest, collection_name, @alice);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_STAKE)]
    public fun test_is_unlocked_fails_if_stake_does_not_exist() {
        let (harvest, _, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_lb::is_unlocked<RewardCoin>(@harvest, collection_name, @alice);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_STAKE)]
    public fun test_unstake_fails_if_stake_not_exists() {
        let (harvest, _, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // unstake when stake not exists
        let token =
            stake_lb::unstake<RewardCoin>(&harvest, @harvest, collection_name, 12345);
        token::deposit_token(&harvest, token);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_STAKE)]
    public fun test_harvest_fails_if_stake_not_exists() {
        let (harvest, _, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // harvest when stake not exists
        let coins =
            stake_lb::harvest<RewardCoin>(&harvest, @harvest, collection_name);
        coin::deposit<RewardCoin>(@harvest, coins);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NOT_ENOUGH_S_BALANCE)]
    public fun test_unstake_fails_if_not_enough_balance() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 99000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 99000000);

        // stake 99 StakeCoins from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 99000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 99000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // wait one week to unstake
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        // unstake more than staked from alice
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 99000001);
        token::deposit_token(&alice_acc, token);

        token::deposit_token(&alice_acc, stake_token);
    }
    // TODO: Check if it is possible to transfer 0 tokens
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_AMOUNT_CANNOT_BE_ZERO)]
    // public fun test_stake_fails_if_amount_is_zero() {
    //     let (harvest, _, collection_owner) = initialize_test();
    //
    //     let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
    //     create_collection(signer::address_of(&collection_owner), collection_name);
    //
    //     // register staking pool with rewards
    //     let stake_token = create_token(&collection_owner, collection_name, string::utf8(b"LB"));
    //     let reward_coins = mint_default_coin<RewardCoin>(12345);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());
    //
    //     let token_id = token::get_token_id(&stake_token);
    //     let token_data_id = token::get_tokendata_id(token_id);
    //     mint_token(&collection_owner, token_data_id,  1);
    //     token::direct_transfer(&collection_owner, &harvest, token_id, 1);
    //
    //     // stake 0 StakeCoins
    //     coin::register<StakeCoin>(&harvest);
    //
    //     // let coins =
    //     //     coin::withdraw<StakeCoin>(&harvest, 0);
    //     let split_token = token::withdraw_token(&harvest, token_id, 0);
    //     stake_lb::stake<RewardCoin>(&harvest, @harvest, split_token);
    //
    //     token::deposit_token(&harvest, stake_token);
    // }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_AMOUNT_CANNOT_BE_ZERO)]
    public fun test_unstake_fails_if_amount_is_zero() {
        let (harvest, _, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // unstake 0 StakeCoins
        let token =
            stake_lb::unstake<RewardCoin>(&harvest, @harvest, collection_name, 0);
        token::deposit_token(&harvest, token);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_AMOUNT_CANNOT_BE_ZERO)]
    public fun test_deposit_reward_coins_fails_if_amount_is_zero() {
        let (harvest, _, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // deposit 0 RewardCoins
        let reward_coins = coin::zero<RewardCoin>();
        stake_lb::deposit_reward_coins<RewardCoin>(&harvest, @harvest, collection_name, reward_coins);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NOTHING_TO_HARVEST)]
    public fun test_harvest_fails_if_nothing_to_harvest_1() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 100000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);

        // stake 100 StakeCoins from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // harvest from alice at the same second
        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);
        coin::deposit<RewardCoin>(@alice, coins);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NOTHING_TO_HARVEST)]
    public fun test_harvest_fails_if_nothing_to_harvest_2() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 100000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);

        // stake 100 StakeCoins from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 10);

        // harvest from alice twice at the same second
        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);
        coin::deposit<RewardCoin>(@alice, coins);
        let coins =
            stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);
        coin::deposit<RewardCoin>(@alice, coins);

        token::deposit_token(&alice_acc, stake_token);
    }
    // TODO: Check whether it is possible to transfer an uninitialized token (without creating a collection, etc.)
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_IS_NOT_COIN)]
    // public fun test_register_fails_if_stake_coin_is_not_coin() {
    //     genesis::setup();
    //
    //     let harvest = new_account(@harvest);
    //     let collection_owner = new_account(@liquidswap_v1_resource_account);
    //     let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
    //     create_collection(signer::address_of(&collection_owner), collection_name);
    //
    //     // create only reward coin
    //     initialize_reward_coin(&harvest, 6);
    //
    //     // register staking pool without stake coin
    //     let stake_token = create_token(&collection_owner, collection_name, string::utf8(b"LB"));
    //     let reward_coins = mint_default_coin<RewardCoin>(12345);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());
    //
    //     token::deposit_token(&harvest, stake_token);
    // }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_IS_NOT_COIN)]
    public fun test_register_fails_if_reward_coin_is_not_coin() {
        genesis::setup();

        let harvest = new_account(@harvest);
        let collection_owner = new_account(@liquidswap_v1_resource_account);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // create only stake coin
        initialize_stake_coin(&harvest, 6);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = coin::zero<RewardCoin>();
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_TOO_EARLY_UNSTAKE)]
    public fun test_unstake_fails_if_executed_before_lockup_end() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 1000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 1000000);

        // stake from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // wait almost a week
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS - 1);

        // unstake from alice
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 1000000);
        token::deposit_token(&alice_acc, token);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_DURATION_CANNOT_BE_ZERO)]
    public fun test_register_fails_if_duration_is_zero() {
        let (harvest, _, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 0;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_DURATION_CANNOT_BE_ZERO)]
    public fun test_deposit_reward_coins_fails_if_duration_is_zero() {
        let (harvest, _, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // deposit rewards less than rew_per_sec pool rate
        let reward_coins = mint_default_coin<RewardCoin>(999999);
        stake_lb::deposit_reward_coins<RewardCoin>(&harvest, @harvest, collection_name, reward_coins);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_HARVEST_FINISHED)]
    public fun test_deposit_reward_coins_fails_after_harvest_is_finished() {
        let (harvest, _, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // wait until pool expired
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // deposit rewards less than rew_per_sec pool rate
        let reward_coins = mint_default_coin<RewardCoin>(1000000);
        stake_lb::deposit_reward_coins<RewardCoin>(&harvest, @harvest, collection_name, reward_coins);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_HARVEST_FINISHED)]
    public fun test_stake_fails_after_harvest_is_finished() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 12345);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 12345);

        // wait until pool expired
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // stake from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 12345);
        let split_token = token::withdraw_token(&alice_acc, token_id, 12345);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        token::deposit_token(&alice_acc, stake_token);
    }

    // #[test]
    // #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED /* ERR_NOT_INITIALIZED */)]
    // fun test_register_without_config_initialization_fails() {
    //     let harvest = new_account(@harvest);
    //
    //     let collection_owner = new_account(@liquidswap_v1_resource_account);
    //     let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
    //     create_collection(signer::address_of(&collection_owner), collection_name);
    //
    //     // initialize_reward_coin(&harvest, 6);
    //
    //     let stake_token = create_token(&collection_owner, collection_name, string::utf8(b"LB"));
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());
    //
    //     token::deposit_token(&harvest, stake_token);
    // }

    // Withdraw rewards tests.

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NOT_WITHDRAW_PERIOD)]
    fun test_withdraw_fails_non_emergency_or_finish() {
        let (harvest, _, collection_owner) = initialize_test();
        let treasury = new_account(@treasury);

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let reward_coins = stake_lb::withdraw_to_treasury<RewardCoin>(
            &treasury,
            @harvest,
            collection_name,
            157680000000000
        );
        coin::deposit(@treasury, reward_coins);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NOT_TREASURY)]
    fun test_withdraw_fails_from_non_treasury_account() {
        let (harvest, emergency, collection_owner) = initialize_test();

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_config::enable_global_emergency(&emergency);

        let reward_coins = stake_lb::withdraw_to_treasury<RewardCoin>(
            &harvest,
            @harvest,
            collection_name,
            157680000000000
        );
        coin::deposit(@harvest, reward_coins);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    fun test_withdraw_in_emergency() {
        let (harvest, emergency, collection_owner) = initialize_test();

        let treasury = new_account(@treasury);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_config::enable_global_emergency(&emergency);

        let reward_coins = stake_lb::withdraw_to_treasury<RewardCoin>(
            &treasury,
            @harvest,
            collection_name,
            157680000000000
        );
        assert!(coin::value(&reward_coins) == 157680000000000, 1);
        coin::register<RewardCoin>(&treasury);
        coin::deposit(@treasury, reward_coins);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    fun test_withdraw_after_period() {
        let (harvest, _, collection_owner) = initialize_test();
        let treasury = new_account(@treasury);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        timestamp::update_global_time_for_test_secs(START_TIME + duration + 7257600);

        let reward_coins = stake_lb::withdraw_to_treasury<RewardCoin>(
            &treasury,
            @harvest,
            collection_name,
            157680000000000
        );
        assert!(coin::value(&reward_coins) == 157680000000000, 1);
        coin::register<RewardCoin>(&treasury);
        coin::deposit(@treasury, reward_coins);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    fun test_withdraw_after_period_plus_emergency() {
        let (harvest, emergency, collection_owner) = initialize_test();
        let treasury = new_account(@treasury);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        timestamp::update_global_time_for_test_secs(START_TIME + duration + 7257600);
        stake_config::enable_global_emergency(&emergency);

        let reward_coins = stake_lb::withdraw_to_treasury<RewardCoin>(
            &treasury,
            @harvest,
            collection_name,
            157680000000000
        );
        assert!(coin::value(&reward_coins) == 157680000000000, 1);
        coin::register<RewardCoin>(&treasury);
        coin::deposit(@treasury, reward_coins);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NOT_WITHDRAW_PERIOD)]
    fun test_withdraw_fails_before_period() {
        let (harvest, _, collection_owner) = initialize_test();
        let treasury = new_account(@treasury);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        timestamp::update_global_time_for_test_secs(START_TIME + duration + 7257599);

        let reward_coins = stake_lb::withdraw_to_treasury<RewardCoin>(
            &treasury,
            @harvest,
            collection_name,
            157680000000000
        );
        coin::deposit(@treasury, reward_coins);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    fun test_withdraw_and_unstake() {
        // i check users can unstake after i withdraw all rewards in 3 months.
        let (harvest, _, collection_owner) = initialize_test();

        let treasury = new_account(@treasury);
        let alice_acc = new_account(@alice);
        let bob_acc = new_account(@bob);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);

        // register staking pool with rewards
        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 5100000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);
        token::direct_transfer(&collection_owner, &bob_acc, token_id, 5000000000);

        // stake 100 StakeCoins from alice
        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // let coins =
        //     coin::withdraw<StakeCoin>(&bob_acc, 5000000000);
        let split_token = token::withdraw_token(&bob_acc, token_id, 5000000000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, split_token);

        // wait 3 months after finish
        timestamp::update_global_time_for_test_secs(START_TIME + duration + 7257600);

        // waithdraw reward coins
        let reward_coins = stake_lb::withdraw_to_treasury<RewardCoin>(
            &treasury,
            @harvest,
            collection_name,
            15768000000000
        );
        coin::register<RewardCoin>(&treasury);
        coin::deposit(@treasury, reward_coins);

        // unstake
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 100000000);
        token::deposit_token(&alice_acc, token);

        let token =
            stake_lb::unstake<RewardCoin>(&bob_acc, @harvest, collection_name, 5000000000);
        token::deposit_token(&bob_acc, token);

        token::deposit_token(&bob_acc, stake_token);
    }

    #[test]
    fun test_stake_after_full_unstake() {
        let (harvest, _, collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        let bob_acc = new_account(@bob);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);

        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 5100000000);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 100000000);
        token::direct_transfer(&collection_owner, &bob_acc, token_id, 5000000000);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // let coins =
        //     coin::withdraw<StakeCoin>(&bob_acc, 100000000);
        let split_token = token::withdraw_token(&bob_acc, token_id, 100000000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, split_token);

        timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);

        let coins = stake_lb::unstake<RewardCoin>(&bob_acc, @harvest, collection_name, 100000000);

        timestamp::update_global_time_for_test_secs(START_TIME + (duration / 2 + 3600));

        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, coins);

        let unlock_time = stake_lb::get_unlock_time<RewardCoin>(@harvest, collection_name, @bob);
        assert!(unlock_time == timestamp::now_seconds() + WEEK_IN_SECONDS, 1);
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // take rewards.
        let rewards = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest, collection_name);
        assert!(coin::value(&rewards) == 7882200000000, 1);
        coin::deposit(@bob, rewards);

        let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);
        assert!(coin::value(&rewards) == 7885800000000, 1);
        coin::deposit(@alice, rewards);

        // unstake.
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 100000000);
        token::deposit_token(&alice_acc, token);

        let token =
            stake_lb::unstake<RewardCoin>(&bob_acc, @harvest, collection_name, 100000000);
        token::deposit_token(&alice_acc, token);

        token::deposit_token(&alice_acc, stake_token);
    }

    // TODO: Incorrect calculation of the accum reward with a large difference in decimals
    #[test]
    fun test_stake_aptos_real_value() {
        // We need to stake Aptos on 20k USD (it's 6060 APT = 8 decimals).
        // Than we need to check how it will work with 30M LP coins (1 decimals).
        // We just checking it not fails, because if it fails, it means it's possible to block rewards.
        let (harvest, _, collection_owner) = initialize_test();

        let duration = 7890000;
        let alice_acc = new_account(@alice);
        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&collection_owner), collection_name);

        coin::register<RewardCoin>(&alice_acc);

        let stake_token = create_stake_token(&collection_owner, collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(606000000000);
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&collection_owner, token_data_id, 30000000000000 + duration);
        token::direct_transfer(&collection_owner, &alice_acc, token_id, 30000000000000 + duration);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 30000000000000);
        let split_token = token::withdraw_token(&alice_acc, token_id, 30000000000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        let i = 1;
        while (i <= 3600) {
            timestamp::update_global_time_for_test_secs(START_TIME + i);

            let token = token::withdraw_token(&alice_acc, token_id, 1);
            stake_lb::stake<RewardCoin>(&alice_acc, @harvest, token);

            i = i + 1;
        };

        // take rewards.
        let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);
        coin::deposit(@alice, rewards);

        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, collection_name);
        coin::deposit(@alice, rewards);

        // unstake.
        let token =
            stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, collection_name, 100000000);
        token::deposit_token(&alice_acc, token);

        token::deposit_token(&alice_acc, stake_token);
    }
}
