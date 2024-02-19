#[test_only]
module harvest::emergency_lb_tests {
    use std::option;
    use std::signer;
    use std::string;

    use aptos_framework::coin;
    use aptos_framework::timestamp;

    use aptos_token::token;

    use harvest::stake_lb;
    use harvest::stake_config;
    use harvest::stake_nft_boost_tests::{create_collecton, create_token};
    use harvest::stake_test_helpers::{
        new_account_with_stake_coins,
        mint_default_coin,
        RewardCoin,
        StakeCoin,
        new_account,
        create_st_collection,
        create_stake_token,
        mint_token
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

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_unstake_with_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        let token = stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, st_collection_name, 100);

        token::deposit_token(&alice_acc, token);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_add_rewards_with_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        stake_lb::deposit_reward_coins<RewardCoin>(&harvest, @harvest, st_collection_name, reward_coins);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_harvest_with_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // wait for rewards
        timestamp::update_global_time_for_test_secs(START_TIME + 100);

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        let reward_coins = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, st_collection_name);
        coin::deposit(@alice, reward_coins);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_boost_with_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);

        let collection_name = string::utf8(b"Test Collection");
        let collection_owner = create_collecton(@collection_owner, collection_name);
        let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool with rewards and boost config
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        let boost_config = stake_lb::create_boost_config(
            @collection_owner,
            collection_name,
            5
        );
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::some(boost_config));

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        // boost stake with nft
        stake_lb::boost<RewardCoin>(&alice_acc, @harvest, st_collection_name, nft);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_claim_with_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        let collection_name = string::utf8(b"Test Collection");
        let collection_owner = create_collecton(@collection_owner, collection_name);
        let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool with rewards and boost config
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        let boost_config = stake_lb::create_boost_config(
            @collection_owner,
            collection_name,
            5
        );
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::some(boost_config));

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // boost stake with nft
        stake_lb::boost<RewardCoin>(&alice_acc, @harvest, st_collection_name, nft);

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        // remove boost
        let nft = stake_lb::remove_boost<RewardCoin>(&alice_acc, @harvest, st_collection_name);

        token::deposit_token(&alice_acc, nft);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_stake_with_global_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 1 * ONE_COIN);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_config::enable_global_emergency(&emergency_admin);

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_unstake_with_global_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        stake_config::enable_global_emergency(&emergency_admin);

        let token = stake_lb::unstake<RewardCoin>(&alice_acc, @harvest, st_collection_name, 100);
        token::deposit_token(&alice_acc, token);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_add_rewards_with_global_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_config::enable_global_emergency(&emergency_admin);

        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        stake_lb::deposit_reward_coins<RewardCoin>(&harvest, @harvest, st_collection_name, reward_coins);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_harvest_with_global_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // wait for rewards
        timestamp::update_global_time_for_test_secs(START_TIME + 100);

        stake_config::enable_global_emergency(&emergency_admin);

        let reward_coins = stake_lb::harvest<RewardCoin>(&alice_acc, @harvest, st_collection_name);
        coin::deposit(@alice, reward_coins);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_boost_with_global_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        let collection_name = string::utf8(b"Test Collection");
        let collection_owner = create_collecton(@collection_owner, collection_name);
        let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool with rewards and boost config
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        let boost_config = stake_lb::create_boost_config(
            @collection_owner,
            collection_name,
            5
        );
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::some(boost_config));

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        stake_config::enable_global_emergency(&emergency_admin);

        // boost stake with nft
        stake_lb::boost<RewardCoin>(&alice_acc, @harvest, st_collection_name, nft);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_claim_with_global_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        let collection_name = string::utf8(b"Test Collection");
        let collection_owner = create_collecton(@collection_owner, collection_name);
        let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool with rewards and boost config
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        let boost_config = stake_lb::create_boost_config(
            @collection_owner,
            collection_name,
            5
        );
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::some(boost_config));

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        // boost stake with nft
        stake_lb::boost<RewardCoin>(&alice_acc, @harvest, st_collection_name, nft);

        stake_config::enable_global_emergency(&emergency_admin);

        // remove boost
        let nft = stake_lb::remove_boost<RewardCoin>(&alice_acc, @harvest, st_collection_name);
        token::deposit_token(&alice_acc, nft);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_enable_local_emergency_if_global_is_enabled() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_config::enable_global_emergency(&emergency_admin);

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NOT_ENOUGH_PERMISSIONS_FOR_EMERGENCY)]
    fun test_cannot_enable_emergency_with_non_admin_account() {
        let (harvest, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_lb::enable_emergency<RewardCoin>(&alice_acc, @harvest, st_collection_name);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_EMERGENCY)]
    fun test_cannot_enable_emergency_twice() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);
        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    fun test_unstake_everything_in_case_of_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);
        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, st_collection_name, @alice) == 1 * ONE_COIN, 1);

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        let (token, nft) = stake_lb::emergency_unstake<RewardCoin>(&alice_acc, @harvest, st_collection_name);
        assert!(token::get_token_amount(&token) == 1 * ONE_COIN, 2);
        assert!(option::is_none(&nft), 1);
        option::destroy_none(nft);
        token::deposit_token(&alice_acc, token);

        assert!(!stake_lb::stake_exists<RewardCoin>(@harvest, st_collection_name, @alice), 3);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    fun test_unstake_everything_and_nft_in_case_of_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        let collection_name = string::utf8(b"Test Collection");
        let collection_owner = create_collecton(@collection_owner, collection_name);
        let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool with rewards and boost config
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        let boost_config = stake_lb::create_boost_config(
            @collection_owner,
            collection_name,
            5
        );
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::some(boost_config));

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, st_collection_name, @alice) == 1 * ONE_COIN, 1);
        stake_lb::boost<RewardCoin>(&alice_acc, @harvest, st_collection_name, nft);

        stake_lb::enable_emergency<RewardCoin>(&emergency_admin, @harvest, st_collection_name);

        let (token, nft) = stake_lb::emergency_unstake<RewardCoin>(&alice_acc, @harvest, st_collection_name);
        assert!(option::is_some(&nft), 1);
        token::deposit_token(&alice_acc, option::extract(&mut nft));
        option::destroy_none(nft);
        assert!(token::get_token_amount(&token) == 1 * ONE_COIN, 2);
        token::deposit_token(&alice_acc, token);

        assert!(!stake_lb::stake_exists<RewardCoin>(@harvest, st_collection_name, @alice), 3);
        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_lb::ERR_NO_EMERGENCY)]
    fun test_cannot_emergency_unstake_in_non_emergency() {
        let (harvest, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        let (token, nft) = stake_lb::emergency_unstake<RewardCoin>(&alice_acc, @harvest, st_collection_name);
        option::destroy_none(nft);
        token::deposit_token(&alice_acc, token);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    fun test_emergency_is_local_to_a_pool() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins_1 = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let reward_coins_2 = mint_default_coin<StakeCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins_1, duration, option::none());
        stake_lb::register_pool<StakeCoin>(&harvest, &stake_token, reward_coins_2, duration, option::none());

        stake_lb::enable_emergency<StakeCoin>(&emergency_admin, @harvest, st_collection_name);

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, st_collection_name, @alice) == 1 * ONE_COIN, 3);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_config::ERR_GLOBAL_EMERGENCY)]
    fun test_cannot_enable_global_emergency_twice() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        stake_config::enable_global_emergency(&emergency_admin);
        stake_config::enable_global_emergency(&emergency_admin);

        token::deposit_token(&harvest, stake_token);
    }

    #[test]
    fun test_unstake_everything_in_case_of_global_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::none());

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, st_collection_name, @alice) == 1 * ONE_COIN, 1);

        stake_config::enable_global_emergency(&emergency_admin);

        let (token, nft) = stake_lb::emergency_unstake<RewardCoin>(&alice_acc, @harvest, st_collection_name);
        assert!(token::get_token_amount(&token) == 1 * ONE_COIN, 2);
        assert!(option::is_none(&nft), 1);
        option::destroy_none(nft);

        token::deposit_token(&alice_acc, token);

        let exists = stake_lb::stake_exists<RewardCoin>(@harvest, st_collection_name, @alice);
        assert!(!exists, 3);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    fun test_unstake_everything_and_nft_in_case_of_global_emergency() {
        let (harvest, emergency_admin, st_collection_owner) = initialize_test();

        let alice_acc = new_account(@alice);

        let collection_name = string::utf8(b"Test Collection");
        let collection_owner = create_collecton(@collection_owner, collection_name);
        let nft = create_token(&collection_owner, collection_name, string::utf8(b"Token"));

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        let boost_config = stake_lb::create_boost_config(
            @collection_owner,
            collection_name,
            5
        );
        stake_lb::register_pool<RewardCoin>(&harvest, &stake_token, reward_coins, duration, option::some(boost_config));

        // mint stake token
        let token_id = token::get_token_id(&stake_token);
        let token_data_id = token::get_tokendata_id(token_id);
        mint_token(&st_collection_owner, token_data_id, 1 * ONE_COIN);
        token::direct_transfer(&st_collection_owner, &alice_acc, token_id, 1 * ONE_COIN);

        // let coins =
        //     coin::withdraw<StakeCoin>(&alice_acc, 1 * ONE_COIN);
        let split_token = token::withdraw_token(&alice_acc, token_id, 1 * ONE_COIN);
        stake_lb::stake<RewardCoin>(&alice_acc, @harvest, split_token);

        assert!(stake_lb::get_user_stake<RewardCoin>(@harvest, st_collection_name, @alice) == 1 * ONE_COIN, 1);
        stake_lb::boost<RewardCoin>(&alice_acc, @harvest, st_collection_name, nft);

        stake_config::enable_global_emergency(&emergency_admin);

        let (token, nft) = stake_lb::emergency_unstake<RewardCoin>(&alice_acc, @harvest, st_collection_name);
        assert!(option::is_some(&nft), 1);
        token::deposit_token(&alice_acc, option::extract(&mut nft));
        option::destroy_none(nft);
        assert!(token::get_token_amount(&token) == 1 * ONE_COIN, 2);
        token::deposit_token(&alice_acc, token);

        assert!(!stake_lb::stake_exists<RewardCoin>(@harvest, st_collection_name, @alice), 3);

        token::deposit_token(&alice_acc, stake_token);
    }

    #[test]
    #[expected_failure(abort_code = stake_config::ERR_NO_PERMISSIONS)]
    fun test_cannot_enable_global_emergency_with_non_admin_account() {
        let (_, _, _) = initialize_test();
        let alice = new_account(@alice);
        stake_config::enable_global_emergency(&alice);
    }

    #[test]
    #[expected_failure(abort_code = stake_config::ERR_NO_PERMISSIONS)]
    fun test_cannot_change_admin_with_non_admin_account() {
        let (_, _, _) = initialize_test();
        let alice = new_account(@alice);
        stake_config::set_emergency_admin_address(&alice, @alice);
    }

    #[test]
    fun test_enable_emergency_with_changed_admin_account() {
        let (_, emergency_admin, st_collection_owner) = initialize_test();
        stake_config::set_emergency_admin_address(&emergency_admin, @alice);

        let alice = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&alice, &stake_token, reward_coins, duration, option::none());

        stake_lb::enable_emergency<RewardCoin>(&alice, @alice, st_collection_name);

        assert!(stake_lb::is_local_emergency<RewardCoin>(@alice, st_collection_name), 1);
        assert!(stake_lb::is_emergency<RewardCoin>(@alice, st_collection_name), 2);
        assert!(!stake_config::is_global_emergency(), 3);

        token::deposit_token(&alice, stake_token);
    }

    #[test]
    fun test_enable_global_emergency_with_changed_admin_account_no_pool() {
        let (_, emergency_admin, _) = initialize_test();
        stake_config::set_emergency_admin_address(&emergency_admin, @alice);

        let alice = new_account(@alice);
        stake_config::enable_global_emergency(&alice);

        assert!(stake_config::is_global_emergency(), 3);
    }

    #[test]
    fun test_enable_global_emergency_with_changed_admin_account_with_pool() {
        let (_, emergency_admin, st_collection_owner) = initialize_test();
        stake_config::set_emergency_admin_address(&emergency_admin, @alice);

        let alice = new_account(@alice);

        // stake token collection
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);

        // register staking pool
        let stake_token = create_stake_token(&st_collection_owner, st_collection_name, string::utf8(b"LB"));
        let reward_coins = mint_default_coin<RewardCoin>(12345 * ONE_COIN);
        let duration = 12345;
        stake_lb::register_pool<RewardCoin>(&alice, &stake_token, reward_coins, duration, option::none());

        stake_config::enable_global_emergency(&alice);

        assert!(!stake_lb::is_local_emergency<RewardCoin>(@alice, st_collection_name), 1);
        assert!(stake_lb::is_emergency<RewardCoin>(@alice, st_collection_name), 2);
        assert!(stake_config::is_global_emergency(), 3);

        token::deposit_token(&emergency_admin, stake_token);
    }

    // Cases for ERR_NOT_INITIALIZED.

    #[test]
    #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED)]
    fun test_enable_global_emergency_not_initialized_fails() {
        let emergency_admin = new_account(@stake_emergency_admin);
        stake_config::enable_global_emergency(&emergency_admin);
    }

    #[test]
    #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED)]
    fun test_is_global_emergency_not_initialized_fails() {
        stake_config::is_global_emergency();
    }

    #[test]
    #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED)]
    fun test_get_emergency_admin_address_not_initialized_fails() {
        stake_config::get_emergency_admin_address();
    }

    #[test]
    #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED)]
    fun test_get_treasury_admin_address_not_initialized_fails() {
        stake_config::get_treasury_admin_address();
    }

    #[test]
    #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED)]
    fun test_set_emergency_admin_address_not_initialized_fails() {
        let emergency_admin = new_account(@stake_emergency_admin);
        stake_config::set_emergency_admin_address(&emergency_admin, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED)]
    fun test_set_treasury_admin_address_not_initialized_fails() {
        let treasury_admin = new_account(@treasury);
        stake_config::set_emergency_admin_address(&treasury_admin, @alice);
    }
}
