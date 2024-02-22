#[test_only]
module harvest::lb_emergency_tests {
    use std::option;
    use std::signer;
    use std::string;
    use std::vector;

    use aptos_framework::coin;
    use aptos_framework::timestamp;

    use aptos_token::token;

    use harvest::stake_lb;
    use harvest::stake_config;
    use harvest::stake_nft_boost_tests::{create_collecton, create_token};
    use harvest::stake_lb_test_helpers::{
        mint_default_coin,
        RewardCoin,
        new_account,
        create_stake_token,
        create_st_collection,
        mint_token,
        create_token_data_id_with_bin_id,
        mint_stake_token
    };
    use harvest::stake_lb_tests::initialize_test;

    /// this is number of decimals in both StakeCoin and RewardCoin by default, named like that for readability
    const ONE_COIN: u64 = 1000000;

    const START_TIME: u64 = 682981200;

    #[test]
    fun test_initialize() {
        let emergency_admin = new_account(@stake_emergency_admin);

        stake_config::initialize(
            &emergency_admin,
            @treasury,
        );

        assert!(stake_config::get_treasury_admin_address() == @treasury, 1);
        assert!(stake_config::get_emergency_admin_address() == @stake_emergency_admin, 1);
        assert!(!stake_config::is_global_emergency(), 1);
    }

    #[test]
    fun test_set_treasury_admin_address() {
        let treasury_acc = new_account(@treasury);
        let emergency_admin = new_account(@stake_emergency_admin);
        let alice_acc = new_account(@alice);

        stake_config::initialize(
            &emergency_admin,
            @treasury,
        );

        stake_config::set_treasury_admin_address(&treasury_acc, @alice);
        assert!(stake_config::get_treasury_admin_address() == @alice, 1);
        stake_config::set_treasury_admin_address(&alice_acc, @treasury);
        assert!(stake_config::get_treasury_admin_address() == @treasury, 1);
    }

    #[test]
    #[expected_failure(abort_code = stake_config::ERR_NO_PERMISSIONS)]
    fun test_set_treasury_admin_address_from_no_permission_account_fails() {
        let emergency_admin = new_account(@stake_emergency_admin);
        let alice_acc = new_account(@alice);

        stake_config::initialize(
            &emergency_admin,
            @treasury,
        );

        stake_config::set_treasury_admin_address(&alice_acc, @treasury);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_register_with_global_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        stake_config::enable_global_emergency(&emergency_admin);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_stake_with_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id = 1;
        let token_data_id = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id);

        // register staking pool with rewards
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id, 1);
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_unstake_with_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id_1 = 1;
        let token_data_id_1 = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id_1);

        // register staking pool
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id_1, 1);
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = mint_stake_token(&st_collection_owner, token_data_id_1, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        let token = stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, st_collection_name, bin_id_1, 100);

        token::deposit_token(&alice_acc, token);
    }

    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    // fun test_cannot_add_rewards_with_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     // register staking pool
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest);
    //
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     stake_lb::deposit_reward_coins<RewardCoin>(&harvest, @harvest, reward_coins, 12345);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    // fun test_cannot_harvest_with_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
    //
    //     // register staking pool
    //     let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
    //     let duration = 15768000;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // wait for rewards
    //     timestamp::update_global_time_for_test_secs(START_TIME + 100);
    //
    //     stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest);
    //
    //     let reward_coins = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     coin::deposit(@alice, reward_coins);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    // fun test_cannot_boost_with_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
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
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest);
    //
    //     // boost stake with nft
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    // fun test_cannot_claim_with_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
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
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // boost stake with nft
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft);
    //
    //     stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest);
    //
    //     // remove boost
    //     let nft = stake_lb::remove_boost<RewardCoin>(&alice_acc, @harvest);
    //     token::deposit_token(&alice_acc, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    // fun test_cannot_stake_with_global_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
    //
    //     // register staking pool
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     stake_config::enable_global_emergency(&emergency_admin);
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    // fun test_cannot_unstake_with_global_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
    //
    //     // register staking pool
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     stake_config::enable_global_emergency(&emergency_admin);
    //
    //     let coins = stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, 100);
    //     coin::deposit(@alice, coins);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    // fun test_cannot_add_rewards_with_global_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     // register staking pool
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     stake_config::enable_global_emergency(&emergency_admin);
    //
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     stake_lb::deposit_reward_coins<RewardCoin>(&harvest, @harvest, reward_coins, 12345);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    // fun test_cannot_harvest_with_global_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
    //
    //     // register staking pool
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // wait for rewards
    //     timestamp::update_global_time_for_test_secs(START_TIME + 100);
    //
    //     stake_config::enable_global_emergency(&emergency_admin);
    //
    //     let reward_coins = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest);
    //     coin::deposit(@alice, reward_coins);
    // }
    //
    //     #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    // fun test_cannot_boost_with_global_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
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
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     stake_config::enable_global_emergency(&emergency_admin);
    //
    //     // boost stake with nft
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    // fun test_cannot_claim_with_global_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
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
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     // boost stake with nft
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft);
    //
    //     stake_config::enable_global_emergency(&emergency_admin);
    //
    //     // remove boost
    //     let nft = stake_lb::remove_boost<RewardCoin>(&alice_acc, @harvest);
    //     token::deposit_token(&alice_acc, nft);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    // fun test_cannot_enable_local_emergency_if_global_is_enabled() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     // register staking pool
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     stake_config::enable_global_emergency(&emergency_admin);
    //
    //     stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NOT_ENOUGH_PERMISSIONS_FOR_EMERGENCY)]
    // fun test_cannot_enable_emergency_with_non_admin_account() {
    //     let (harvest, _) = initialize_test();
    //
    //     let alice_acc = new_account(@alice);
    //
    //     // register staking pool
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     stake_lb::enable_emergency<RewardCoin>(&alice_acc, @harvest);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    // fun test_cannot_enable_emergency_twice() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     // register staking pool
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest);
    //     stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest);
    // }

    #[test]
    fun test_unstake_everything_in_case_of_emergency_with_one_bin_id() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id_1 = 1;
        let token_data_id_1 = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id_1);

        // register staking pool
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id_1, 1);
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        let split_token = mint_stake_token(&st_collection_owner, token_data_id_1, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);
        assert!(
            stake_lb::get_user_stake<RewardCoin>(@harvest, st_collection_name, @alice) == ((1 * ONE_COIN) as u128),
            1
        );

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        let (tokens, nft) = stake_lb::emergency_unstake<RewardCoin>(&alice_acc, @harvest, st_collection_name);
        assert!(vector::length(&tokens) == 1, 2);

        let token = vector::pop_back(&mut tokens);

        assert!(token::get_token_amount(&token) == 1 * ONE_COIN, 2);
        assert!(option::is_none(&nft), 1);

        option::destroy_none(nft);
        token::deposit_token(&alice_acc, token);
        vector::destroy_empty(tokens);

        assert!(!stake_lb::stake_exists<RewardCoin>(@harvest, st_collection_name, @alice), 3);
    }

    #[test]
    fun test_unstake_everything_in_case_of_emergency_with_three_bin_id() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id_1 = 1;
        let bin_id_2 = 2;
        let bin_id_3 = 3;
        let token_data_id_1 = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id_1);
        let token_data_id_2 = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id_2);
        let token_data_id_3 = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id_3);
        mint_token(&st_collection_owner, token_data_id_1, 1);
        mint_token(&st_collection_owner, token_data_id_2, 1);
        mint_token(&st_collection_owner, token_data_id_3, 1);

        // register staking pool
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id_1, 1);
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        let split_token_1 = mint_stake_token(&st_collection_owner, token_data_id_1, 1 * ONE_COIN);
        let split_token_2 = mint_stake_token(&st_collection_owner, token_data_id_2, 1 * ONE_COIN);
        let split_token_3 = mint_stake_token(&st_collection_owner, token_data_id_3, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token_1);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token_2);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token_3);
        assert!(
            stake_lb::get_user_stake<RewardCoin>(@harvest, st_collection_name, @alice) == ((3 * ONE_COIN) as u128),
            1
        );

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        let (tokens, nft) = stake_lb::emergency_unstake<RewardCoin>(&alice_acc, @harvest, st_collection_name);
        assert!(vector::length(&tokens) == 3, 2);

        let length = vector::length(&tokens);
        for (i in 0..length) {
            let token = vector::pop_back(&mut tokens);

            assert!(token::get_token_amount(&token) == 1 * ONE_COIN, 2);
            assert!(option::is_none(&nft), 1);

            token::deposit_token(&alice_acc, token);
        };

        option::destroy_none(nft);
        vector::destroy_empty(tokens);

        assert!(!stake_lb::stake_exists<RewardCoin>(@harvest, st_collection_name, @alice), 3);
    }

    // #[test]
    // fun test_unstake_everything_and_nft_in_case_of_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
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
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //     assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, @alice) == 1 * ONE_COIN, 1);
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft);
    //
    //     stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest);
    //
    //     let (coins, nft) = stake_lb::emergency_unstake<RewardCoin>(&alice_acc, @harvest);
    //     assert!(option::is_some(&nft), 1);
    //     token::deposit_token(&alice_acc, option::extract(&mut nft));
    //     option::destroy_none(nft);
    //     assert!(coin::value(&coins) == 1 * ONE_COIN, 2);
    //     coin::deposit(@alice, coins);
    //
    //     assert!(!stake_lb::stake_exists<RewardCoin>(@harvest, @alice), 3);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_lb::ERR_NO_EMERGENCY)]
    // fun test_cannot_emergency_unstake_in_non_emergency() {
    //     let (harvest, _) = initialize_test();
    //
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
    //
    //     // register staking pool
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //
    //     let (coins, nft) = stake_lb::emergency_unstake<RewardCoin>(&alice_acc, @harvest);
    //     option::destroy_none(nft);
    //     coin::deposit(@alice, coins);
    // }
    //
    // #[test]
    // fun test_emergency_is_local_to_a_pool() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
    //
    //     // register staking pool
    //     let reward_coins_1 = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let reward_coins_2 = mint_default_coin<StakeCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins_1, duration, option::none());
    //     stake_lb::register_pool<RewardCoin, StakeCoin>(&harvest, reward_coins_2, duration, option::none());
    //
    //     stake_lb::enable_emergency<RewardCoin, StakeCoin>(&emergency_admin, @harvest);
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //     assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, @alice) == 1 * ONE_COIN, 3);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_config::ERR_GLOBAL_EMERGENCY)]
    // fun test_cannot_enable_global_emergency_twice() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     // register staking pool
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     stake_config::enable_global_emergency(&emergency_admin);
    //     stake_config::enable_global_emergency(&emergency_admin);
    // }
    //
    // #[test]
    // fun test_unstake_everything_in_case_of_global_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
    //
    //     // register staking pool
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&harvest, reward_coins, duration, option::none());
    //
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //     assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, @alice) == 1 * ONE_COIN, 1);
    //
    //     stake_config::enable_global_emergency(&emergency_admin);
    //
    //     let (coins, nft) = stake_lb::emergency_unstake<RewardCoin>(&alice_acc, @harvest);
    //     assert!(coin::value(&coins) == 1 * ONE_COIN, 2);
    //     assert!(option::is_none(&nft), 1);
    //     option::destroy_none(nft);
    //     coin::deposit(@alice, coins);
    //
    //     let exists = stake_lb::stake_exists<RewardCoin>(@harvest, @alice);
    //     assert!(!exists, 3);
    // }
    //
    // #[test]
    // fun test_unstake_everything_and_nft_in_case_of_global_emergency() {
    //     let (harvest, emergency_admin) = initialize_test();
    //
    //     let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);
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
    //     let coins =
    //         coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
    //     stake_lb::stake<RewardCoin>(&alice_acc, @harvest, coins);
    //     assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, @alice) == 1 * ONE_COIN, 1);
    //     stake_lb::boost<RewardCoin>(&alice_acc, @harvest, nft);
    //
    //     stake_config::enable_global_emergency(&emergency_admin);
    //
    //     let (coins, nft) = stake_lb::emergency_unstake<RewardCoin>(&alice_acc, @harvest);
    //     assert!(option::is_some(&nft), 1);
    //     token::deposit_token(&alice_acc, option::extract(&mut nft));
    //     option::destroy_none(nft);
    //     assert!(coin::value(&coins) == 1 * ONE_COIN, 2);
    //     coin::deposit(@alice, coins);
    //
    //     assert!(!stake_lb::stake_exists<RewardCoin>(@harvest, @alice), 3);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_config::ERR_NO_PERMISSIONS)]
    // fun test_cannot_enable_global_emergency_with_non_admin_account() {
    //     let (_, _) = initialize_test();
    //     let alice = new_account(@alice);
    //     stake_config::enable_global_emergency(&alice);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_config::ERR_NO_PERMISSIONS)]
    // fun test_cannot_change_admin_with_non_admin_account() {
    //     let (_, _) = initialize_test();
    //     let alice = new_account(@alice);
    //     stake_config::set_emergency_admin_address(&alice, @alice);
    // }
    //
    // #[test]
    // fun test_enable_emergency_with_changed_admin_account() {
    //     let (_, emergency_admin) = initialize_test();
    //     stake_config::set_emergency_admin_address(&emergency_admin, @alice);
    //
    //     let alice = new_account(@alice);
    //
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&alice, reward_coins, duration, option::none());
    //
    //     stake_lb::enable_emergency<RewardCoin>(&alice, @alice);
    //
    //     assert!(stake_lb::is_local_emergency<RewardCoin>(@alice), 1);
    //     assert!(stake_lb::is_emergency<RewardCoin>(@alice), 2);
    //     assert!(!stake_config::is_global_emergency(), 3);
    // }
    //
    // #[test]
    // fun test_enable_global_emergency_with_changed_admin_account_no_pool() {
    //     let (_, emergency_admin) = initialize_test();
    //     stake_config::set_emergency_admin_address(&emergency_admin, @alice);
    //
    //     let alice = new_account(@alice);
    //     stake_config::enable_global_emergency(&alice);
    //
    //     assert!(stake_config::is_global_emergency(), 3);
    // }
    //
    // #[test]
    // fun test_enable_global_emergency_with_changed_admin_account_with_pool() {
    //     let (_, emergency_admin) = initialize_test();
    //     stake_config::set_emergency_admin_address(&emergency_admin, @alice);
    //
    //     let alice = new_account(@alice);
    //
    //     let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
    //     let duration = 12345;
    //     stake_lb::register_pool<RewardCoin>(&alice, reward_coins, duration, option::none());
    //
    //     stake_config::enable_global_emergency(&alice);
    //
    //     assert!(!stake_lb::is_local_emergency<RewardCoin>(@alice), 1);
    //     assert!(stake_lb::is_emergency<RewardCoin>(@alice), 2);
    //     assert!(stake_config::is_global_emergency(), 3);
    // }
    //
    // // Cases for ERR_NOT_INITIALIZED.
    //
    // #[test]
    // #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED)]
    // fun test_enable_global_emergency_not_initialized_fails() {
    //     let emergency_admin = new_account(@stake_emergency_admin);
    //     stake_config::enable_global_emergency(&emergency_admin);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED)]
    // fun test_is_global_emergency_not_initialized_fails() {
    //     stake_config::is_global_emergency();
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED)]
    // fun test_get_emergency_admin_address_not_initialized_fails() {
    //     stake_config::get_emergency_admin_address();
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED)]
    // fun test_get_treasury_admin_address_not_initialized_fails() {
    //     stake_config::get_treasury_admin_address();
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED)]
    // fun test_set_emergency_admin_address_not_initialized_fails() {
    //     let emergency_admin = new_account(@stake_emergency_admin);
    //     stake_config::set_emergency_admin_address(&emergency_admin, @alice);
    // }
    //
    // #[test]
    // #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED)]
    // fun test_set_treasury_admin_address_not_initialized_fails() {
    //     let treasury_admin = new_account(@treasury);
    //     stake_config::set_emergency_admin_address(&treasury_admin, @alice);
    // }
}
