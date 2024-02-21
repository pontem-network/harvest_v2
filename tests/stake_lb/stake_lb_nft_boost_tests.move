#[test_only]
module harvest::stake_lb_nft_boost_tests {
    use std::option;
    use std::signer;
    use std::string::{Self, String};
    use aptos_std::debug::print;

    use aptos_framework::coin;
    use aptos_framework::timestamp;

    use aptos_token::token::{Self, Token};

    use harvest::stake_lb;
    use harvest::stake_lb_test_helpers::{new_account, StakeCoin, RewardCoin, new_account_with_stake_coins, mint_default_coin,
        create_stake_token,
        create_st_collection,
        create_token_data_id_with_bin_id,
        mint_token,
        mint_stake_token
    };
    use harvest::stake_lb_tests::initialize_test;

    // week in seconds, lockup period
    const WEEK_IN_SECONDS: u64 = 604800;

    const START_TIME: u64 = 682981200;

    public fun create_collecton(owner_addr: address, collection_name: String): signer {
        let collection_owner = new_account(owner_addr);

        token::create_collection(
            &collection_owner,
            collection_name,
            string::utf8(b"Some Description"),
            string::utf8(b"https://aptos.dev"),
            50,
            vector<bool>[false, false, false]
        );

        collection_owner
    }

    public fun create_token(collection_owner: &signer, collection_name: String, name: String): Token {
        token::create_token_script(
            collection_owner,
            collection_name,
            name,
            string::utf8(b"Some Description"),
            1,
            1,
            string::utf8(b"https://aptos.dev"),
            @collection_owner,
            100,
            0,
            vector<bool>[ false, false, false, false, false, false ],
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
        );
        let token_id = token::create_token_id_raw(@collection_owner, collection_name, name, 0);

        token::withdraw_token(collection_owner, token_id, 1)
    }

    #[test]
    public fun test_register_with_boost_config() {
        let (_, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);
        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        let collection_name = string::utf8(b"Test Collection");
        create_collecton(@collection_owner, collection_name);

        // register staking pool with rewards and boost config
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        let boost_config = stake_lb::create_boost_config(
            @collection_owner,
            collection_name,
            5
        );
        stake_lb::register_pool<RewardCoin>(
            &alice_acc,
            &stake_token,
            reward_coins,
            duration,
            option::some(boost_config)
        );

        // check pool statistics
        let (reward_per_sec, accum_reward, last_updated, reward_amount, scale) =
            stake_lb::get_pool_info<RewardCoin>(@alice, st_collection_name);
        let end_ts = stake_lb::get_end_timestamp<RewardCoin>(@alice, st_collection_name);
        assert!(end_ts == START_TIME + duration, 1);
        assert!(reward_per_sec == 1000000, 1);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME, 1);
        assert!(reward_amount == 15768000000000, 1);
        // assert!(scale == 1000000000000, 1); // stake token decimals = 6
        assert!(scale == 1000000, 1);
        assert!(stake_lb::get_pool_total_stake<RewardCoin>(@alice, st_collection_name) == 0, 1);

        // check boost config
        let (collection_owner_addr, coll_name, boost_percent) =
            stake_lb::get_boost_config<RewardCoin>(@alice, st_collection_name);
        assert!(collection_owner_addr == @collection_owner, 1);
        assert!(coll_name == collection_name, 1);
        assert!(boost_percent == 5, 1);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    public fun test_boost_and_remove_boost() {
        let (harvest, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id = 1;
        let token_data_id = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id);

        let collection_name = string::utf8(b"Test Collection");
        let collection_owner = create_collecton(@collection_owner, collection_name);
        let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));

        // register staking pool with rewards and boost config
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id, 1);
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        let boost_config = stake_lb::create_boost_config(
            @collection_owner,
            collection_name,
            5
        );
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::some(boost_config));
        token::deposit_token(&st_collection_owner, stake_token);

        // stake 500 StakeCoins from alice
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 500000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // boost stake with nft
        stake_lb::boost<RewardCoin>(&alice_acc, @harvest, st_collection_name, nft);

        // check values
        let total_boosted = stake_lb::get_pool_total_boosted<RewardCoin>(@harvest, st_collection_name);
        let user_boosted = stake_lb::get_user_boosted<RewardCoin>(@harvest, st_collection_name, @alice);
        assert!(total_boosted == 25000000, 1);
        assert!(user_boosted == 25000000, 1);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 10);

        let pending_rewards = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, st_collection_name, @alice);
        // assert!(pending_rewards == 9999999, 1); // stake token decimals > 2
        assert!(pending_rewards == 9999675, 1);

        // remove nft boost
        let nft = stake_lb::remove_boost<RewardCoin>(&alice_acc, @harvest, st_collection_name);
        token::deposit_token(&alice_acc, nft);

        // check values
        let total_boosted = stake_lb::get_pool_total_boosted<RewardCoin>(@harvest, st_collection_name);
        let user_boosted = stake_lb::get_user_boosted<RewardCoin>(@harvest, st_collection_name, @alice);
        assert!(total_boosted == 0, 1);
        assert!(user_boosted == 0, 1);

    }

    // #[test]
    // public fun test_remove_boost_works_after_pool_duration_end() {
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1500000000);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));
    //
    //     // register staking pool with rewards and boost config
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         5
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     // stake 500 StakeCoins from alice
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // boost stake with nft
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft);
    //
    //     // wait until pool expired and a week more
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS);
    //
    //     // remove nft boost
    //     let nft = stake_lb::remove_boost<RewardCoin>(&alice_acc, @harvest);
    //     token::deposit_token(&alice_acc, nft);
    //
    //     // check values
    //     let total_boosted = stake_lb::get_pool_total_boosted<RewardCoin>(@harvest);
    //     let user_boosted = stake_lb::get_user_boosted<RewardCoin>(@harvest, @alice);
    //     assert!(total_boosted == 0, 1);
    //     assert!(user_boosted == 0, 1);
    // }
    //
    #[test]
    public fun test_reward_calculation_with_boost_and_one_bin_id() {
        let (harvest, _, st_collection_owner) = initialize_test();
        let alice_acc = new_account(@alice);
        let bob_acc = new_account(@bob);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id = 1;
        let token_data_id = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id);

        let collection_name = string::utf8(b"Test Collection");
        let collection_owner = create_collecton(@collection_owner, collection_name);
        let nft_1 = create_token(&collection_owner, collection_name, string::utf8(b"Token 1"));
        let nft_2 = create_token(&collection_owner, collection_name, string::utf8(b"Token 2"));

        // register staking pool with rewards and boost config
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id, 1);
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        let boost_config = stake_lb::create_boost_config(
            @collection_owner,
            collection_name,
            100
        );
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::some(boost_config));
        token::deposit_token(&st_collection_owner, stake_token);

        // stake 100 StakeCoins from alice
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 100000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // stake 100 StakeCoins from bob
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 100000000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, split_token);

        // boost stake with nft from alice
        stake_lb::boost<RewardCoin>(&alice_acc, @harvest, st_collection_name, nft_1);

        // wait one week seconds
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        let pending_rewards_1 = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, st_collection_name, @alice);
        let pending_rewards_2 = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, st_collection_name, @bob);
        assert!(pending_rewards_1 == 403200000000, 1);
        assert!(pending_rewards_2 == 201600000000, 1);

        // unstake 50 StakeCoins from alice
        let token = stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, st_collection_name, bin_id, 50000000);
        token::deposit_token(&alice_acc, token);

        // boost stake with nft from bob
        stake_lb::boost<RewardCoin>(&bob_acc, @harvest, st_collection_name, nft_2);

        // wait 100 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS + 100);

        let pending_rewards_1 = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, st_collection_name, @alice);
        let pending_rewards_2 = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, st_collection_name, @bob);

        // assert!(pending_rewards_1 == 403233333333, 1); // stake token decimals > 2
        // assert!(pending_rewards_2 == 201666666666, 1); // stake token decimals > 2
        print<u64>(&pending_rewards_1);
        print<u64>(&pending_rewards_2);
        assert!(pending_rewards_1 == 403233333300, 1);
        assert!(pending_rewards_2 == 201666666600, 1);

        // unstake 50 StakeCoins from alice
        let token = stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, st_collection_name, bin_id, 50000000);
        token::deposit_token(&alice_acc, token);

        // stake 50 StakeCoins from bob
        // let split_token = token::withdraw_token(&bob_acc, token_id, 50000000);
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 50000000);
        stake_lb::stake<RewardCoin>(&bob_acc, @harvest, split_token);

        // wait 100 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS + 200);

        let pending_rewards_1 = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, st_collection_name, @alice);
        let pending_rewards_2 = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, st_collection_name, @bob);

        // assert!(pending_rewards_1 == 403233333333, 1); // stake token decimals > 2
        // assert!(pending_rewards_2 == 201766666666, 1); // stake token decimals > 2
        assert!(pending_rewards_1 == 403233333300, 1);
        assert!(pending_rewards_2 == 201766666500, 1);

        // stake 150 StakeCoins from alice
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 150000000);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // remove nft boost from bob
        let nft_2 = stake_lb::remove_boost<RewardCoin>(&bob_acc, @harvest, st_collection_name);
        token::deposit_token(&bob_acc, nft_2);

        // wait 100 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS + 300);

        let pending_rewards_1 = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, st_collection_name, @alice);
        let pending_rewards_2 = stake_lb::get_pending_user_rewards<RewardCoin>(@harvest, st_collection_name, @bob);

        // assert!(pending_rewards_1 == 403300000000, 1); // stake token decimals > 2
        // assert!(pending_rewards_2 == 201800000000, 1); // stake token decimals > 2
        assert!(pending_rewards_1 == 403299999900, 1);
        assert!(pending_rewards_2 == 201799999800, 1);

        let rewards_1 = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, st_collection_name);
        let rewards_2 = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest, st_collection_name);
        let amount_1 = coin::value(&rewards_1);
        let amount_2 = coin::value(&rewards_2);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);
        coin::deposit(@alice, rewards_1);
        coin::deposit(@bob, rewards_2);

        // assert!(amount_1 == 403300000000, 1); // stake token decimals > 2
        // assert!(amount_2 == 201800000000, 1); // stake token decimals > 2
        assert!(amount_1 == 403299999900, 1);
        assert!(amount_2 == 201799999800, 1);

        // 0 RewardCoin lost during calculations
        let total_rewards = (WEEK_IN_SECONDS + 300) * 1000000;
        let total_earned = amount_1 + amount_2;
        let losed_rewards = total_rewards - total_earned;

        // assert!(losed_rewards == 0, 1); // stake token decimals > 2
        assert!(losed_rewards == 300, 1);
    }

    // #[test]
    // public fun test_boosted_amount_calculation() {
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1500000000);
    //     let bob_acc = new_account_with_stake_coins(@bob, 1500000000);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let nft_1 = create_token(&collection_owner, collection_name, string::utf8(b"Token 1"));
    //     let nft_2 = create_token(&collection_owner, collection_name, string::utf8(b"Token 2"));
    //
    //     // register staking pool with rewards and boost config
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         1
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     // stake 500 StakeCoins from alice
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // check values
    //     let total_boosted = stake_lb::get_pool_total_boosted<RewardCoin>(@harvest);
    //     let user_boosted = stake_lb::get_user_boosted<RewardCoin>(@harvest, @alice);
    //     assert!(total_boosted == 0, 1);
    //     assert!(user_boosted == 0, 1);
    //
    //     // boost alice stake with nft
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft_1);
    //
    //     // check values
    //     let total_boosted = stake_lb::get_pool_total_boosted<RewardCoin>(@harvest);
    //     let user_boosted = stake_lb::get_user_boosted<RewardCoin>(@harvest, @alice);
    //     assert!(total_boosted == 5000000, 1);
    //     assert!(user_boosted == 5000000, 1);
    //
    //     // stake 10 StakeCoin from alice
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 10000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // check values
    //     let total_boosted = stake_lb::get_pool_total_boosted<RewardCoin>(@harvest);
    //     let user_boosted = stake_lb::get_user_boosted<RewardCoin>(@harvest, @alice);
    //     assert!(total_boosted == 5100000, 1);
    //     assert!(user_boosted == 5100000, 1);
    //
    //     // stake 800 StakeCoins from bob
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 800000000);
    //     stake_lb::stake<RewardCoin>(&bob_acc, @harvest, coins);
    //
    //     // boost bob stake with nft
    //     stake_lb::boost<RewardCoin>(&bob_acc, @harvest, nft_2);
    //
    //     // check values
    //     let total_boosted = stake_lb::get_pool_total_boosted<RewardCoin>(@harvest);
    //     let user_boosted = stake_lb::get_user_boosted<RewardCoin>(@harvest, @bob);
    //     assert!(total_boosted == 13100000, 1);
    //     assert!(user_boosted == 8000000, 1);
    //
    //     // remove boost from bob
    //     let nft_2 = stake_lb::remove_boost<RewardCoin>(&bob_acc, @harvest);
    //     token::deposit_token(&bob_acc, nft_2);
    //
    //     // check values
    //     let total_boosted = stake_lb::get_pool_total_boosted<RewardCoin>(@harvest);
    //     let user_boosted = stake_lb::get_user_boosted<RewardCoin>(@harvest, @bob);
    //     assert!(total_boosted == 5100000, 1);
    //     assert!(user_boosted == 0, 1);
    //
    //     // wait one week to unstake
    //     timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);
    //
    //     // unstake 255 StakeCoins from alice
    //     let coins =
    //         stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, 255000000);
    //     coin::deposit(@alice, coins);
    //
    //     // check values
    //     let total_boosted = stake_lb::get_pool_total_boosted<RewardCoin>(@harvest);
    //     let user_boosted = stake_lb::get_user_boosted<RewardCoin>(@harvest, @alice);
    //     assert!(total_boosted == 2550000, 1);
    //     assert!(user_boosted == 2550000, 1);
    //
    //     // unstake 255 StakeCoins from alice
    //     let coins =
    //         stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, 255000000);
    //     coin::deposit(@alice, coins);
    //
    //     // check values
    //     let total_boosted = stake_lb::get_pool_total_boosted<RewardCoin>(@harvest);
    //     let user_boosted = stake_lb::get_user_boosted<RewardCoin>(@harvest, @alice);
    //     assert!(total_boosted == 0, 1);
    //     assert!(user_boosted == 0, 1);
    // }
    //
    // // todo: update this test after PR35 merge
    // #[test]
    // public fun test_is_boostable() {
    //     let (harvest, _) = initialize_test();
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     create_collecton(@collection_owner, collection_name);
    //
    //     // register staking pool 1 with rewards and boost config
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         100
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     // register staking pool 2 with rewards no boost config
    //     let reward_coins = mint_default_coin<StakeCoin>(15768000000000);
    //     let duration = 15768000;
    //     stake_lb::register_pool<RewardCoin, StakeCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     // check is boostable
    //     assert!(stake_lb::is_boostable<RewardCoin>(@harvest), 1);
    //     assert!(!stake_lb::is_boostable<RewardCoin, StakeCoin>(@harvest), 1);
    // }
    //
    // #[test]
    // public fun test_is_boosted() {
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 500000000);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let nft_1 = create_token(&collection_owner, collection_name, string::utf8(b"Token"));
    //
    //     // register staking pool with rewards and boost config
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         100
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     // stake 500 StakeCoins from alice
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     assert!(!stake_lb::is_boosted<RewardCoin>(@harvest, @alice), 1);
    //
    //     // boost alice stake with nft
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft_1);
    //
    //     assert!(stake_lb::is_boosted<RewardCoin>(@harvest, @alice), 1);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_POOL)]
    // public fun test_boost_fails_if_pool_does_not_exist() {
    //     let (harvest, _) = initialize_test();
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));
    //
    //     stake_lb::boost<RewardCoin>(&harvest, @harvest, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_POOL)]
    // public fun test_remove_boost_fails_if_pool_does_not_exist() {
    //     let (harvest, _) = initialize_test();
    //
    //     let nft = stake_lb::remove_boost<RewardCoin>(&harvest, @harvest);
    //     token::deposit_token(&harvest, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_POOL)]
    // public fun test_is_boostable_fails_if_pool_does_not_exist() {
    //     stake_lb::is_boostable<RewardCoin>(@harvest);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_POOL)]
    // public fun test_get_boost_config_fails_if_pool_does_not_exist() {
    //     stake_lb::get_boost_config<RewardCoin>(@harvest);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_POOL)]
    // public fun test_get_pool_total_boosted_fails_if_pool_does_not_exist() {
    //     stake_lb::get_pool_total_boosted<RewardCoin>(@harvest);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_POOL)]
    // public fun test_is_boosted_fails_if_pool_does_not_exist() {
    //     stake_lb::is_boosted<RewardCoin>(@harvest, @alice);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_POOL)]
    // public fun test_get_user_boosted_fails_if_pool_does_not_exist() {
    //     stake_lb::get_user_boosted<RewardCoin>(@harvest, @alice);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_STAKE)]
    // public fun test_boost_fails_if_stake_does_not_exist() {
    //     let (harvest, _) = initialize_test();
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token 1"));
    //
    //     // register staking pool with rewards and boost config
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         5
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     stake_lb::boost<RewardCoin>(&harvest, @harvest, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_STAKE)]
    // public fun test_remove_boost_fails_if_stake_does_not_exist() {
    //     let (harvest, _) = initialize_test();
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     create_collecton(@collection_owner, collection_name);
    //
    //     // register staking pool with rewards
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     let nft = stake_lb::remove_boost<RewardCoin>(&harvest, @harvest);
    //     token::deposit_token(&harvest, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_STAKE)]
    // public fun test_is_boosted_fails_if_stake_not_exists() {
    //     let (harvest, _) = initialize_test();
    //
    //     // register staking pool with rewards
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     stake_lb::get_user_boosted<RewardCoin>(@harvest, @alice);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_STAKE)]
    // public fun test_get_user_boosted_fails_if_stake_not_exists() {
    //     let (harvest, _) = initialize_test();
    //
    //     // register staking pool with rewards
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     stake_lb::get_user_boosted<RewardCoin>(@harvest, @alice);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_COLLECTION)]
    // public fun test_create_boost_config_fails_if_colleciont_does_not_exist_1() {
    //     let (harvest, _) = initialize_test();
    //
    //     create_collecton(@collection_owner, string::utf8(b"Test Collection"));
    //
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         string::utf8(b"Wrong Collection"),
    //         5
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, coin::zero<RewardCoin>(), 12345, option::some(boost_config));
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = 0x60001, location = aptos_token::token)]
    // public fun test_create_boost_config_fails_if_colleciont_does_not_exist_2() {
    //     let (harvest, _) = initialize_test();
    //
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         string::utf8(b"Test Collection"),
    //         5
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, coin::zero<RewardCoin>(), 12345, option::some(boost_config));
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_INVALID_BOOST_PERCENT)]
    // public fun test_create_boost_config_fails_if_boost_percent_less_then_min() {
    //     let (harvest, _) = initialize_test();
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     create_collecton(@collection_owner, collection_name);
    //
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         0
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, coin::zero<RewardCoin>(), 12345, option::some(boost_config));
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_INVALID_BOOST_PERCENT)]
    // public fun test_create_boost_config_fails_if_boost_percent_more_then_max() {
    //     let (harvest, _) = initialize_test();
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     create_collecton(@collection_owner, collection_name);
    //
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         101
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, coin::zero<RewardCoin>(), 12345, option::some(boost_config));
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NON_BOOST_POOL)]
    // public fun test_boost_fails_when_non_boost_pool() {
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 500000000);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));
    //
    //     // register staking pool with rewards
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     // stake 500 StakeCoins from alice
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // boost stake with nft
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NON_BOOST_POOL)]
    // public fun test_get_boost_config_fails_when_non_boost_pool() {
    //     let (harvest, _) = initialize_test();
    //
    //     // register staking pool with rewards
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     stake_lb::get_boost_config<RewardCoin>(@harvest);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_ALREADY_BOOSTED)]
    // public fun test_boost_fails_if_already_boosted() {
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1500000000);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let nft_1 = create_token(&collection_owner, collection_name, string::utf8(b"Token 1"));
    //     let nft_2 = create_token(&collection_owner, collection_name, string::utf8(b"Token 2"));
    //
    //     // register staking pool with rewards and boost config
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         5
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     // stake 500 StakeCoins from alice
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // boost stake with nft twice
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft_1);
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft_2);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_WRONG_TOKEN_COLLECTION)]
    // public fun test_boost_fails_if_token_from_wrong_collection_1() {
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1500000000);
    //
    //     let collection_name_1 = string::utf8(b"Test Collection 1");
    //     let collection_name_2 = string::utf8(b"Test Collection 2");
    //     let collection_owner = create_collecton(@collection_owner, collection_name_1);
    //     create_collecton(@collection_owner, collection_name_2);
    //     let nft = create_token(&collection_owner, collection_name_2, string::utf8(b"Token"));
    //
    //     // register staking pool with rewards and boost config
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name_1,
    //         5
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     // stake 500 StakeCoins from alice
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // boost stake with nft
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_WRONG_TOKEN_COLLECTION)]
    // public fun test_boost_fails_if_token_from_wrong_collection_2() {
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1500000000);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     create_collecton(@bob, collection_name);
    //     let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));
    //
    //     // register staking pool with rewards and boost config
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @bob,
    //         collection_name,
    //         5
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     // stake 500 StakeCoins from alice
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // boost stake with nft
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_BOOST)]
    // public fun test_remove_boost_fails_when_executed_with_non_boost_pool() {
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1500000000);
    //
    //     // register staking pool with rewards and boost config
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     // stake 500 StakeCoins from alice
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // remove boost
    //     let nft = stake_lb::remove_boost<RewardCoin>(&alice_acc, @harvest);
    //     token::deposit_token(&alice_acc, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_BOOST)]
    // public fun test_remove_boost_fails_if_executed_before_boost() {
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1500000000);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     create_collecton(@collection_owner, collection_name);
    //
    //     // register staking pool with rewards and boost config
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         5
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     // stake 500 StakeCoins from alice
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // remove boost
    //     let nft = stake_lb::remove_boost<RewardCoin>(&alice_acc, @harvest);
    //     token::deposit_token(&alice_acc, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_BOOST)]
    // public fun test_remove_boost_fails_when_executed_twice() {
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1500000000);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));
    //
    //     // register staking pool with rewards and boost config
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         5
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     // stake 500 StakeCoins from alice
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // boost stake with nft
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft);
    //
    //     // remove nft boost twice
    //     let nft = stake_lb::remove_boost<RewardCoin>(&alice_acc, @harvest);
    //     token::deposit_token(&alice_acc, nft);
    //     let nft = stake_lb::remove_boost<RewardCoin>(&alice_acc, @harvest);
    //     token::deposit_token(&alice_acc, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NFT_AMOUNT_MORE_THAN_ONE)]
    // public fun test_boost_fails_if_amount_more_than_one() {
    //     let (harvest, _) = initialize_test();
    //     let bob_acc = new_account_with_stake_coins(@bob, 1000);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let token_name = string::utf8(b"Token");
    //
    //     token::create_token_script(
    //         &collection_owner,
    //         collection_name,
    //         token_name,
    //         string::utf8(b"Some Description"),
    //         2,
    //         2,
    //         string::utf8(b"https://aptos.dev"),
    //         @collection_owner,
    //         100,
    //         0,
    //         vector<bool>[ false, false, false, false, false, false ],
    //         vector<String>[],
    //         vector<vector<u8>>[],
    //         vector<String>[],
    //     );
    //     let token_id = token::create_token_id_raw(@collection_owner, collection_name, token_name, 0);
    //     let nft = token::withdraw_token(&collection_owner, token_id, 2);
    //
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         1
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     // stake 800 StakeCoins from bob
    //     let coins =
    //         coin::withdraw<StakeCoin>(&bob_acc, 1000);
    //     stake_lb::stake<RewardCoin>(&bob_acc, @harvest, coins);
    //
    //     stake_lb::boost<RewardCoin>(&bob_acc, @harvest, nft);
    // }
    //
    // #[test]
    // public fun test_stake_and_boost_two_accounts_in_time() {
    //     // * stake two accounts.
    //     // * after some time add boost.
    //     // * remove boost.
    //     // * check values during steps.
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1500000000);
    //     let bob_acc = new_account_with_stake_coins(@bob, 1500000000);
    //
    //     coin::register<RewardCoin>(&alice_acc);
    //     coin::register<RewardCoin>(&bob_acc);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));
    //
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         100
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&bob_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&bob_acc, @harvest, coins);
    //
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&rewards) == 3942000000000, 1);
    //     coin::deposit(@alice, rewards);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest);
    //     assert!(coin::value(&rewards) == 3942000000000, 1);
    //     coin::deposit(@bob, rewards);
    //
    //     stake_lb::boost<RewardCoin>(&bob_acc, @harvest, nft);
    //
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration - 3600);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&rewards) == 2626800000000, 1);
    //     coin::deposit(@alice, rewards);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest);
    //     assert!(coin::value(&rewards) == 5253600000000, 1);
    //     coin::deposit(@bob, rewards);
    //
    //     let nft = stake_lb::remove_boost<RewardCoin>(&bob_acc, @harvest);
    //     token::deposit_token(&bob_acc, nft);
    //
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&rewards) == 1800000000, 1);
    //     coin::deposit(@alice, rewards);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest);
    //     assert!(coin::value(&rewards) == 1800000000, 1);
    //     coin::deposit(@bob, rewards);
    // }
    //
    // #[test]
    // public fun test_stake_and_boost_two_accounts_and_additional_stake() {
    //     // * stake two accounts.
    //     // * after some time add boost.
    //     // * add additional stake.
    //     // * remove stake.
    //     // * check values during steps.
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1500000000);
    //     let bob_acc = new_account_with_stake_coins(@bob, 1500000000);
    //
    //     coin::register<RewardCoin>(&alice_acc);
    //     coin::register<RewardCoin>(&bob_acc);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));
    //
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         100
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&bob_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&bob_acc, @harvest, coins);
    //
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&rewards) == 3942000000000, 1);
    //     coin::deposit(@alice, rewards);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest);
    //     assert!(coin::value(&rewards) == 3942000000000, 1);
    //     coin::deposit(@bob, rewards);
    //
    //     stake_lb::boost<RewardCoin>(&bob_acc, @harvest, nft);
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&bob_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&bob_acc, @harvest, coins);
    //
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration - 3600);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&rewards) == 1576080000000, 1);
    //     coin::deposit(@alice, rewards);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest);
    //     assert!(coin::value(&rewards) == 6304320000000, 1);
    //     coin::deposit(@bob, rewards);
    //
    //     let nft = stake_lb::remove_boost<RewardCoin>(&bob_acc, @harvest);
    //     token::deposit_token(&bob_acc, nft);
    //
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&rewards) == 1200000000, 1);
    //     coin::deposit(@alice, rewards);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest);
    //     assert!(coin::value(&rewards) == 2400000000, 1);
    //     coin::deposit(@bob, rewards);
    // }
    //
    // #[test]
    // public fun test_stake_and_boost_two_accounts_and_unstake() {
    //     // * stake two accounts.
    //     // * after some time add boost.
    //     // * unstake.
    //     // * check values during steps.
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1500000000);
    //     let bob_acc = new_account_with_stake_coins(@bob, 1500000000);
    //
    //     coin::register<RewardCoin>(&alice_acc);
    //     coin::register<RewardCoin>(&bob_acc);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));
    //
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         100
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&bob_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&bob_acc, @harvest, coins);
    //
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&rewards) == 3942000000000, 1);
    //     coin::deposit(@alice, rewards);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest);
    //     assert!(coin::value(&rewards) == 3942000000000, 1);
    //     coin::deposit(@bob, rewards);
    //
    //     stake_lb::boost<RewardCoin>(&bob_acc, @harvest, nft);
    //
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration - 3600);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&rewards) == 2626800000000, 1);
    //     coin::deposit(@alice, rewards);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest);
    //     assert!(coin::value(&rewards) == 5253600000000, 1);
    //     coin::deposit(@bob, rewards);
    //
    //     let stake_coins = stake_lb::unstake<RewardCoin>(&bob_acc, @harvest, 500000000);
    //     coin::deposit(@bob, stake_coins);
    //
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&rewards) == 3600000000, 1);
    //     coin::deposit(@alice, rewards);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NOTHING_TO_HARVEST)]
    // public fun test_stake_and_boost_two_accounts_and_unstake_harvest_fails() {
    //     // * stake two accounts.
    //     // * after some time add boost.
    //     // * unstake.
    //     // * trying to harvest just keeping nft later.
    //     let (harvest, _) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1500000000);
    //     let bob_acc = new_account_with_stake_coins(@bob, 1500000000);
    //
    //     coin::register<RewardCoin>(&alice_acc);
    //     coin::register<RewardCoin>(&bob_acc);
    //
    //     let collection_name = string::utf8(b"Test Collection");
    //     let collection_owner = create_collecton(@collection_owner, collection_name);
    //     let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));
    //
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     let boost_config = stake_lb::create_boost_config(
    //         @collection_owner,
    //         collection_name,
    //         100
    //     );
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::some(boost_config));
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&bob_acc, 500000000);
    //     stake_lb::stake<RewardCoin>(&bob_acc, @harvest, coins);
    //
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&rewards) == 3942000000000, 1);
    //     coin::deposit(@alice, rewards);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest);
    //     assert!(coin::value(&rewards) == 3942000000000, 1);
    //     coin::deposit(@bob, rewards);
    //
    //     stake_lb::boost<RewardCoin>(&bob_acc, @harvest, nft);
    //
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration - 3600);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&rewards) == 2626800000000, 1);
    //     coin::deposit(@alice, rewards);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest);
    //     assert!(coin::value(&rewards) == 5253600000000, 1);
    //     coin::deposit(@bob, rewards);
    //
    //     let stake_coins = stake_lb::unstake<RewardCoin>(&bob_acc, @harvest, 500000000);
    //     coin::deposit(@bob, stake_coins);
    //
    //     timestamp::update_global_time_for_test_secs(START_TIME + duration);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&rewards) == 3600000000, 1);
    //     coin::deposit(@alice, rewards);
    //
    //     let rewards = stake_lb::harvest<RewardCoin>(&bob_acc, @harvest);
    //     assert!(coin::value(&rewards) == 3600000000, 1);
    //     coin::deposit(@bob, rewards);
    // }
}
