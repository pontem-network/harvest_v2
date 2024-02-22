#[test_only]
module harvest::staking_lb_epochs_tests_move {
    use std::option;
    use std::signer;
    use std::string;

    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_token::token;

    use harvest::stake_lb;
    use harvest::stake_lb_test_helpers::{
        amount,
        mint_default_coin,
        StakeCoin as S,
        RewardCoin as R,
        new_account_with_stake_coins,
        create_st_collection,
        create_token_data_id_with_bin_id,
        mint_stake_token,
        mint_token
    };
    use harvest::stake_lb_tests::initialize_test;

    // week in seconds, lockup period
    const WEEK_IN_SECONDS: u64 = 604800;

    const START_TIME: u64 = 682981200;

    // // todo: remove
    // fun print_epoch(epoch: u64) {
    //     let (rewards_amount, reward_per_sec, accum_reward, start_time, last_update_time, end_time, distributed, ended_at)
    //         = stake_lb::get_epoch_info<R>(@harvest, epoch);
    //     std::debug::print(&aptos_std::string_utils::format1(&b"Epoch INFO: {}", epoch));
    //     std::debug::print(&aptos_std::string_utils::format1(&b"rewards_amount = {}", rewards_amount));
    //     std::debug::print(&aptos_std::string_utils::format1(&b"reward_per_sec = {}", reward_per_sec));
    //     std::debug::print(&aptos_std::string_utils::format1(&b"accum_reward = {}", accum_reward));
    //     std::debug::print(&aptos_std::string_utils::format1(&b"start_time = {}", start_time));
    //     std::debug::print(&aptos_std::string_utils::format1(&b"last_update_time = {}", last_update_time));
    //     std::debug::print(&aptos_std::string_utils::format1(&b"end_time = {}", end_time));
    //     std::debug::print(&aptos_std::string_utils::format1(&b"distributed = {}", distributed));
    //     std::debug::print(&aptos_std::string_utils::format1(&b"ended_at = {}", ended_at));
    //     std::debug::print(&aptos_std::string_utils::format1(&b"is_ghost = {}\n", reward_per_sec == 0));
    // }
    // fun print_line() {
    //     std::debug::print(&std::string::utf8(b"============================================================================"));
    // }

    // Deposit reward on different epoch stages test

    #[test]
    public fun test_deposit_twice_same_sec() {
        let (harvest, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, amount<S>(100, 0));
        coin::register<R>(&alice_acc);

        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id = 1;
        let token_data_id = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id);

        // register staking pool with rewards
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id, 1);
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        let duration = 500;
        stake_lb::register_pool<R>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        // check 0 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, start_time,
            last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);
        assert!(rewards_amount == amount<R>(1000, 0), 1);
        assert!(reward_per_sec == amount<R>(2, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME, 1);
        assert!(last_update_time == START_TIME, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == 0, 1);

        // stake 100 from alice
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 100);
        stake_lb::stake<R>(&alice_acc, @harvest, split_token);

        // create new epoch, take some rewards from previous
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        stake_lb::deposit_reward_coins<R>(&alice_acc, @harvest, st_collection_name, reward_coins, 500);
        let curr_epoch = stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name);
        assert!(curr_epoch == 1, 0);

        // check 0 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);
        assert!(accum_reward == 0, 1);
        assert!(last_update_time == START_TIME, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == START_TIME, 1);

        // check 1 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, start_time,
            last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 1);
        // 1000 new + 1000 from prev epoch
        assert!(rewards_amount == amount<R>(2000, 0), 1);
        assert!(reward_per_sec == amount<R>(4, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME, 1);
        assert!(last_update_time == START_TIME, 1);
        assert!(end_time == START_TIME + 500, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == 0, 1);

        // wait full second epoch
        timestamp::update_global_time_for_test_secs(START_TIME + 500);

        // check all rewards was distributed
        let rew = stake_lb::harvest<R>(&alice_acc, @harvest, st_collection_name);
        assert!(coin::value(&rew) == amount<R>(2000, 0), 1);

        // check 1 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 1);
        assert!(accum_reward == 2000_0000_000000, 1);
        assert!(last_update_time == START_TIME + 500, 1);
        assert!(end_time == START_TIME + 500, 1);
        assert!(distributed == amount<R>(2000, 0), 1);
        assert!(ended_at == START_TIME + 500, 1);

        coin::deposit(@alice, rew);
    }

    //
    #[test]
    public fun test_deposit_rew_on_unfinished_rew_epoch_with_one_bin_id() {
        let (harvest, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, amount<S>(100, 0));
        coin::register<R>(&alice_acc);

        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id = 1;
        let token_data_id = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id);

        // register staking pool with rewards
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id, 1);
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        let duration = 500;
        stake_lb::register_pool<R>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        // check 0 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, start_time,
            last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);
        assert!(rewards_amount == amount<R>(1000, 0), 1);
        assert!(reward_per_sec == amount<R>(2, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME, 1);
        assert!(last_update_time == START_TIME, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == 0, 1);

        // stake 100 from alice
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 100);
        stake_lb::stake<R>(&alice_acc, @harvest, split_token);

        // wait half of epoch
        timestamp::update_global_time_for_test_secs(START_TIME + 250);

        // create new epoch, take some rewards from previous
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        stake_lb::deposit_reward_coins<R>(&alice_acc, @harvest, st_collection_name, reward_coins, 500);
        let curr_epoch = stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name);
        assert!(curr_epoch == 1, 0);

        // check 0 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);
        assert!(accum_reward == 500_0000_000000, 1);
        assert!(last_update_time == START_TIME + 250, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == amount<R>(500, 0), 1);
        assert!(ended_at == START_TIME + 250, 1);

        // check 1 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, start_time,
            last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 1);
        // 1000 new + 500 from prev epoch
        assert!(rewards_amount == amount<R>(1500, 0), 1);
        assert!(reward_per_sec == amount<R>(3, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME + 250, 1);
        assert!(last_update_time == START_TIME + 250, 1);
        assert!(end_time == START_TIME + 250 + 500, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == 0, 1);

        // wait full epoch 1
        timestamp::update_global_time_for_test_secs(START_TIME + 250 + 500);

        // check all rewards was distributed
        let rew = stake_lb::harvest<R>(&alice_acc, @harvest, st_collection_name);
        assert!(coin::value(&rew) == amount<R>(2000, 0), 1);

        // check 1 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 1);
        assert!(accum_reward == 1500_0000_000000, 1);
        assert!(last_update_time == START_TIME + 250 + 500, 1);
        assert!(end_time == START_TIME + 250 + 500, 1);
        assert!(distributed == amount<R>(1500, 0), 1);
        assert!(ended_at == START_TIME + 250 + 500, 1);

        coin::deposit(@alice, rew);
    }

    #[test]
    public fun test_deposit_rew_on_unfinished_rew_epoch_with_two_bin_id() {
        let (harvest, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, amount<S>(100, 0));
        coin::register<R>(&alice_acc);

        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id_1 = 1;
        let bin_id_2 = 2;
        let token_data_id_1 = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id_1);
        let token_data_id_2 = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id_2);
        mint_token(&st_collection_owner, token_data_id_2, 1);

        // register staking pool with rewards
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id_1, 1);
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        let duration = 500;
        stake_lb::register_pool<R>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        // check 0 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, start_time,
            last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);
        assert!(rewards_amount == amount<R>(1000, 0), 1);
        assert!(reward_per_sec == amount<R>(2, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME, 1);
        assert!(last_update_time == START_TIME, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == 0, 1);

        // stake 100 from alice
        let split_token_1 = mint_stake_token(&st_collection_owner, token_data_id_1, 50);
        stake_lb::stake<R>(&alice_acc, @harvest, split_token_1);

        let split_token_2 = mint_stake_token(&st_collection_owner, token_data_id_2, 50);
        stake_lb::stake<R>(&alice_acc, @harvest, split_token_2);

        // wait half of epoch
        timestamp::update_global_time_for_test_secs(START_TIME + 250);

        // create new epoch, take some rewards from previous
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        stake_lb::deposit_reward_coins<R>(&alice_acc, @harvest, st_collection_name, reward_coins, 500);
        let curr_epoch = stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name);
        assert!(curr_epoch == 1, 0);

        // check 0 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);
        assert!(accum_reward == 500_0000_000000, 1);
        assert!(last_update_time == START_TIME + 250, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == amount<R>(500, 0), 1);
        assert!(ended_at == START_TIME + 250, 1);

        // check 1 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, start_time,
            last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 1);
        // 1000 new + 500 from prev epoch
        assert!(rewards_amount == amount<R>(1500, 0), 1);
        assert!(reward_per_sec == amount<R>(3, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME + 250, 1);
        assert!(last_update_time == START_TIME + 250, 1);
        assert!(end_time == START_TIME + 250 + 500, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == 0, 1);

        // wait full epoch 1
        timestamp::update_global_time_for_test_secs(START_TIME + 250 + 500);

        // check all rewards was distributed
        let rew = stake_lb::harvest<R>(&alice_acc, @harvest, st_collection_name);
        assert!(coin::value(&rew) == amount<R>(2000, 0), 1);

        // check 1 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 1);
        assert!(accum_reward == 1500_0000_000000, 1);
        assert!(last_update_time == START_TIME + 250 + 500, 1);
        assert!(end_time == START_TIME + 250 + 500, 1);
        assert!(distributed == amount<R>(1500, 0), 1);
        assert!(ended_at == START_TIME + 250 + 500, 1);

        coin::deposit(@alice, rew);
    }

    #[test]
    public fun test_deposit_rew_on_finished_this_sec_rew_epoch() {
        let (harvest, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, amount<S>(100, 0));
        coin::register<R>(&alice_acc);

        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id = 1;
        let token_data_id = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id);

        // register staking pool with rewards
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id, 1);
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        let duration = 500;
        stake_lb::register_pool<R>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        // check 0 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, start_time,
            last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);
        assert!(rewards_amount == amount<R>(1000, 0), 1);
        assert!(reward_per_sec == amount<R>(2, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME, 1);
        assert!(last_update_time == START_TIME, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == 0, 1);

        // stake 100 from alice
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 100);
        stake_lb::stake<R>(&alice_acc, @harvest, split_token);

        // wait full epoch
        timestamp::update_global_time_for_test_secs(START_TIME + 500);

        // create new epoch
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        stake_lb::deposit_reward_coins<R>(&alice_acc, @harvest, st_collection_name, reward_coins, 500);
        let curr_epoch = stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name);
        assert!(curr_epoch == 2, 0);

        // check 0 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);
        assert!(accum_reward == 1000_0000_000000, 1);
        assert!(last_update_time == START_TIME + duration, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == amount<R>(1000, 0), 1);
        assert!(ended_at == START_TIME + duration, 1);

        // Below epoch appeared as a result of an edge case when the epoch creation
        // transaction came at the second of the end of the previous epoch

        // check 1 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, start_time,
            last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 1);
        assert!(rewards_amount == 0, 1);
        assert!(reward_per_sec == 0, 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME + 500, 1);
        assert!(last_update_time == START_TIME + 500, 1);
        assert!(end_time == START_TIME + 500, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == START_TIME + 500, 1);

        // check 2 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, start_time,
            last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 2);
        assert!(rewards_amount == amount<R>(1000, 0), 1);
        assert!(reward_per_sec == amount<R>(2, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME + 500, 1);
        assert!(last_update_time == START_TIME + 500, 1);
        assert!(end_time == START_TIME + 500 + 500, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == 0, 1);

        // wait full epoch 2
        timestamp::update_global_time_for_test_secs(START_TIME + 500 + 500);

        // check all rewards was distributed
        let rew = stake_lb::harvest<R>(&alice_acc, @harvest, st_collection_name);
        assert!(coin::value(&rew) == amount<R>(2000, 0), 1);

        // check 1 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 2);
        assert!(accum_reward == 1000_0000_000000, 1);
        assert!(last_update_time == START_TIME + 500 + 500, 1);
        assert!(end_time == START_TIME + 500 + 500, 1);
        assert!(distributed == amount<R>(1000, 0), 1);
        assert!(ended_at == START_TIME + 500 + 500, 1);

        coin::deposit(@alice, rew);
    }

    #[test]
    public fun test_deposit_rew_on_long_time_ago_finished_rew_epoch() {
        let (harvest, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, amount<S>(100, 0));
        coin::register<R>(&alice_acc);
        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id = 1;
        let token_data_id = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id);

        // register staking pool with rewards
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id, 1);

        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        let duration = 500;
        stake_lb::register_pool<R>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        // check 0 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, start_time,
            last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);
        assert!(rewards_amount == amount<R>(1000, 0), 1);
        assert!(reward_per_sec == amount<R>(2, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME, 1);
        assert!(last_update_time == START_TIME, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == 0, 1);

        // stake 100 from alice
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 100);
        stake_lb::stake<R>(&alice_acc, @harvest, split_token);

        // wait full epoch + one year
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS * 52);

        // create new epoch
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        stake_lb::deposit_reward_coins<R>(&alice_acc, @harvest, st_collection_name, reward_coins, 500);
        let curr_epoch = stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name);
        assert!(curr_epoch == 2, 0);

        // check 0 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);
        assert!(accum_reward == 1000_0000_000000, 1);
        assert!(last_update_time == START_TIME + WEEK_IN_SECONDS * 52, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == amount<R>(1000, 0), 1);
        assert!(ended_at == START_TIME + WEEK_IN_SECONDS * 52, 1);

        // check 1 (ghost) epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, start_time,
            last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 1);
        assert!(rewards_amount == 0, 1);
        assert!(reward_per_sec == 0, 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME + duration, 1);
        assert!(last_update_time == START_TIME + WEEK_IN_SECONDS * 52, 1);
        assert!(end_time == START_TIME + WEEK_IN_SECONDS * 52, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == START_TIME + WEEK_IN_SECONDS * 52, 1);

        // check 2 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, start_time,
            last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 2);
        assert!(rewards_amount == amount<R>(1000, 0), 1);
        assert!(reward_per_sec == amount<R>(2, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME + WEEK_IN_SECONDS * 52, 1);
        assert!(last_update_time == START_TIME + WEEK_IN_SECONDS * 52, 1);
        assert!(end_time == START_TIME + WEEK_IN_SECONDS * 52 + 500, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == 0, 1);

        // wait full epoch 2
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS * 52 + 500);

        // check all rewards was distributed
        let rew = stake_lb::harvest<R>(&alice_acc, @harvest, st_collection_name);
        assert!(coin::value(&rew) == amount<R>(2000, 0), 1);

        // check 2 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 2);
        assert!(accum_reward == 1000_0000_000000, 1);
        assert!(last_update_time == START_TIME + WEEK_IN_SECONDS * 52 + 500, 1);
        assert!(end_time == START_TIME + WEEK_IN_SECONDS * 52 + 500, 1);
        assert!(distributed == amount<R>(1000, 0), 1);
        assert!(ended_at == START_TIME + WEEK_IN_SECONDS * 52 + 500, 1);

        coin::deposit(@alice, rew);
    }

    #[test]
    public fun test_rewards_accumulating_after_ghost_epoch() {
        let (harvest, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, amount<S>(100, 0));
        coin::register<R>(&alice_acc);

        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id = 1;
        let token_data_id = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id);

        // register staking pool with rewards
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id, 1);
        let reward_coins = mint_default_coin<R>(amount<R>(157680000, 0));
        let duration = 15768000;
        stake_lb::register_pool<R>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        // stake some coins
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 100);
        stake_lb::stake<R>(&alice_acc, @harvest, split_token);

        // check accum reward
        stake_lb::recalculate_user_stake<R>(@harvest, st_collection_name, @alice);
        let curr_epoch = stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name);
        let (_, _, accum_reward, _, last_updated, _, _, _)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, curr_epoch);
        let reward_val = stake_lb::get_pending_user_rewards<R>(@harvest, st_collection_name, @alice);
        assert!(reward_val == 0, 1);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME, 1);
        assert!(curr_epoch == 0, 1);

        // wait half of duration & check accum reward
        timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);
        stake_lb::recalculate_user_stake<R>(@harvest, st_collection_name, @alice);
        let curr_epoch = stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name);
        let (_, _, accum_reward, _, last_updated, _, _, _)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, curr_epoch);
        let reward_val = stake_lb::get_pending_user_rewards<R>(@harvest, st_collection_name, @alice);
        assert!(reward_val == amount<R>(78840000, 0), 1);
        assert!(accum_reward == 788400000000000000, 1);
        assert!(last_updated == START_TIME + duration / 2, 1);
        assert!(curr_epoch == 0, 1);

        // wait full duration & check accum reward
        timestamp::update_global_time_for_test_secs(START_TIME + duration);
        stake_lb::recalculate_user_stake<R>(@harvest, st_collection_name, @alice);
        let curr_epoch = stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name);
        let (_, _, accum_reward, _, last_updated, _, _, _)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);
        let reward_val = stake_lb::get_pending_user_rewards<R>(@harvest, st_collection_name, @alice);
        assert!(reward_val == amount<R>(157680000, 0), 1);
        assert!(accum_reward == 1576800000000000000, 1);
        assert!(last_updated == START_TIME + duration, 1);
        assert!(curr_epoch == 1, 1);

        // wait full duration + 1 sec & check accum reward
        timestamp::update_global_time_for_test_secs(START_TIME + duration + 1);
        stake_lb::recalculate_user_stake<R>(@harvest, st_collection_name, @alice);
        let curr_epoch = stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name);
        let (_, _, accum_reward, _, last_updated, _, _, _)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, curr_epoch);
        let reward_val = stake_lb::get_pending_user_rewards<R>(@harvest, st_collection_name, @alice);
        assert!(reward_val == amount<R>(157680000, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME + duration + 1, 1);
        assert!(curr_epoch == 1, 1);

        // wait full duration + 200 weeks & check accum reward
        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS * 200);
        stake_lb::recalculate_user_stake<R>(@harvest, st_collection_name, @alice);
        let curr_epoch = stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name);
        let (_, _, accum_reward, _, last_updated, _, _, _)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, curr_epoch);
        let reward_val = stake_lb::get_pending_user_rewards<R>(@harvest, st_collection_name, @alice);
        assert!(reward_val == amount<R>(157680000, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME + duration + WEEK_IN_SECONDS * 200, 1);
        assert!(curr_epoch == 1, 1);

        // check user can get rewards after ghost epoch

        // create new epoch
        let reward_coins = mint_default_coin<R>(amount<R>(150, 0));
        stake_lb::deposit_reward_coins<R>(&alice_acc, @harvest, st_collection_name, reward_coins, 150);

        // wait full epoch duration & check accum reward
        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS * 200 + 150);
        stake_lb::recalculate_user_stake<R>(@harvest, st_collection_name, @alice);
        let curr_epoch = stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name);
        let (_, _, accum_reward, _, last_updated, _, _, _)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 2);
        let reward_val = stake_lb::get_pending_user_rewards<R>(@harvest, st_collection_name, @alice);
        assert!(reward_val == amount<R>(157680000, 0) + amount<R>(150, 0), 1);
        assert!(accum_reward == 1500000000000, 1);
        assert!(last_updated == START_TIME + duration + WEEK_IN_SECONDS * 200 + 150, 1);
        assert!(curr_epoch == 3, 1);

        let gain = stake_lb::harvest<R>(&alice_acc, @harvest, st_collection_name);
        assert!(coin::value(&gain) == amount<R>(157680000, 0) + amount<R>(150, 0), 1);
        coin::deposit(@alice, gain);
    }

    // tests with few users

    #[test]
    public fun test_few_users_rewards_changing_with_one_bin_id() {
        let (harvest, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, amount<S>(100, 0));
        let bob_acc = new_account_with_stake_coins(@bob, amount<S>(100, 0));
        coin::register<R>(&alice_acc);
        coin::register<R>(&bob_acc);

        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id = 1;
        let token_data_id = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id);

        // register staking pool with rewards
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id, 1);
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        let duration = 5_000_000;
        stake_lb::register_pool<R>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        // stake 100 from alice
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 100000000);
        stake_lb::stake<R>(&alice_acc, @harvest, split_token);

        // wait half of first epoch
        timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);

        // stake 100 from bob
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, 100000000);
        stake_lb::stake<R>(&bob_acc, @harvest, split_token);

        // wait till the end of first epoch
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // create new epoch
        let reward_coins = mint_default_coin<R>(amount<R>(5000, 0));
        stake_lb::deposit_reward_coins<R>(&alice_acc, @harvest, st_collection_name, reward_coins, 500);
        assert!(stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name) == 2, 0);

        // wait half of second epoch
        timestamp::update_global_time_for_test_secs(START_TIME + duration + 500 / 2);

        // unstake for alice
        let token = stake_lb::unstake<R>(&alice_acc, @harvest, st_collection_name, bin_id, 100000000);
        token::deposit_token(&alice_acc, token);

        // wait till the end of second epoch
        timestamp::update_global_time_for_test_secs(START_TIME + duration + 500);
        let token = stake_lb::unstake<R>(&bob_acc, @harvest, st_collection_name, bin_id, 100000000);
        token::deposit_token(&bob_acc, token);

        let rewards = stake_lb::harvest<R>(&alice_acc, @harvest, st_collection_name);
        assert!(coin::value(&rewards) == amount<R>(2000, 0), 1);
        coin::deposit(@alice, rewards);

        let rewards = stake_lb::harvest<R>(&bob_acc, @harvest, st_collection_name);
        assert!(coin::value(&rewards) == amount<R>(4000, 0), 1);
        coin::deposit(@bob, rewards);

        // check 0 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);

        // assert!(accum_reward == 7_500000000000, 1); // if decimals stake token = 6
        assert!(accum_reward == 7500000, 1);
        assert!(last_update_time == START_TIME + duration, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == amount<R>(1000, 0), 1);
        assert!(ended_at == START_TIME + duration, 1);

        // check 1 (ghost) epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, _, _, _, _, _)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 1);
        assert!(rewards_amount == 0, 1);
        assert!(reward_per_sec == 0, 1);
        assert!(accum_reward == 0, 1);

        // check 2 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 2);
        // assert!(accum_reward == 37_500000000000, 1); // if decimals stake token = 6
        assert!(accum_reward == 37500000, 1);
        assert!(last_update_time == START_TIME + duration + 500, 1);
        assert!(end_time == START_TIME + duration + 500, 1);
        assert!(distributed == amount<R>(5000, 0), 1);
        assert!(ended_at == START_TIME + duration + 500, 1);
    }

    #[test]
    public fun test_few_users_rewards_changing_with_two_bin_id() {
        let (harvest, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, amount<S>(100, 0));
        let bob_acc = new_account_with_stake_coins(@bob, amount<S>(100, 0));
        coin::register<R>(&alice_acc);
        coin::register<R>(&bob_acc);

        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id_1 = 1;
        let bin_id_2 = 2;
        let token_data_id_1 = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id_1);
        let token_data_id_2 = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id_2);
        mint_token(&st_collection_owner, token_data_id_2, 1);

        // register staking pool with rewards
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id_1, 1);
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        let duration = 5_000_000;
        stake_lb::register_pool<R>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        // stake 100 from alice
        let split_token_1 = mint_stake_token(&st_collection_owner, token_data_id_1, 50000000);
        let split_token_2 = mint_stake_token(&st_collection_owner, token_data_id_2, 50000000);
        stake_lb::stake<R>(&alice_acc, @harvest, split_token_1);
        stake_lb::stake<R>(&alice_acc, @harvest, split_token_2);

        // wait half of first epoch
        timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);

        // stake 100 from bob
        let split_token = mint_stake_token(&st_collection_owner, token_data_id_1, 100000000);
        stake_lb::stake<R>(&bob_acc, @harvest, split_token);

        // wait till the end of first epoch
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // create new epoch
        let reward_coins = mint_default_coin<R>(amount<R>(5000, 0));
        stake_lb::deposit_reward_coins<R>(&alice_acc, @harvest, st_collection_name, reward_coins, 500);
        assert!(stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name) == 2, 0);

        // wait half of second epoch
        timestamp::update_global_time_for_test_secs(START_TIME + duration + 500 / 2);

        // unstake for alice
        let token_1 = stake_lb::unstake<R>(&alice_acc, @harvest, st_collection_name, bin_id_1, 50000000);
        let token_2 = stake_lb::unstake<R>(&alice_acc, @harvest, st_collection_name, bin_id_2, 50000000);
        token::deposit_token(&alice_acc, token_1);
        token::deposit_token(&alice_acc, token_2);

        // wait till the end of second epoch
        timestamp::update_global_time_for_test_secs(START_TIME + duration + 500);
        let token = stake_lb::unstake<R>(&bob_acc, @harvest, st_collection_name, bin_id_1, 100000000);
        token::deposit_token(&bob_acc, token);

        let rewards = stake_lb::harvest<R>(&alice_acc, @harvest, st_collection_name);
        assert!(coin::value(&rewards) == amount<R>(2000, 0), 1);
        coin::deposit(@alice, rewards);

        let rewards = stake_lb::harvest<R>(&bob_acc, @harvest, st_collection_name);
        assert!(coin::value(&rewards) == amount<R>(4000, 0), 1);
        coin::deposit(@bob, rewards);

        // check 0 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 0);

        // assert!(accum_reward == 7_500000000000, 1); // if decimals stake token = 6
        assert!(accum_reward == 7500000, 1);
        assert!(last_update_time == START_TIME + duration, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == amount<R>(1000, 0), 1);
        assert!(ended_at == START_TIME + duration, 1);

        // check 1 (ghost) epoch fields
        let (rewards_amount, reward_per_sec, accum_reward, _, _, _, _, _)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 1);
        assert!(rewards_amount == 0, 1);
        assert!(reward_per_sec == 0, 1);
        assert!(accum_reward == 0, 1);

        // check 2 epoch fields
        let (_, _, accum_reward, _, last_update_time, end_time, distributed, ended_at)
            = stake_lb::get_epoch_info<R>(@harvest, st_collection_name, 2);
        // assert!(accum_reward == 37_500000000000, 1); // if decimals stake token = 6
        assert!(accum_reward == 37500000, 1);
        assert!(last_update_time == START_TIME + duration + 500, 1);
        assert!(end_time == START_TIME + duration + 500, 1);
        assert!(distributed == amount<R>(5000, 0), 1);
        assert!(ended_at == START_TIME + duration + 500, 1);
    }

    #[test]
    public fun test_few_rew_epochs_no_users_then_two_users() {
        let (harvest, _, st_collection_owner) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, amount<S>(100, 0));
        let bob_acc = new_account_with_stake_coins(@bob, amount<S>(100, 0));
        coin::register<R>(&alice_acc);
        coin::register<R>(&bob_acc);

        let st_collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_st_collection(signer::address_of(&st_collection_owner), st_collection_name);
        let bin_id = 1;
        let token_data_id = create_token_data_id_with_bin_id(&st_collection_owner, st_collection_name, bin_id);

        // register staking pool with rewards
        let stake_token = mint_stake_token(&st_collection_owner, token_data_id, 1);
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        let duration = 500;
        stake_lb::register_pool<R>(&harvest, &stake_token, reward_coins, duration, option::none());
        token::deposit_token(&st_collection_owner, stake_token);

        // wait till the end of first epoch and a minute more
        timestamp::update_global_time_for_test_secs(START_TIME + duration + 60);

        // create new epoch
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        stake_lb::deposit_reward_coins<R>(&alice_acc, @harvest, st_collection_name, reward_coins, 500);
        assert!(stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name) == 2, 0);

        // wait till the end of first epoch and a minute more
        timestamp::update_global_time_for_test_secs(START_TIME + duration * 2 + 120);

        // create new epoch
        let reward_coins = mint_default_coin<R>(amount<R>(1200, 0));
        stake_lb::deposit_reward_coins<R>(&alice_acc, @harvest, st_collection_name, reward_coins, 6_000_000);
        assert!(stake_lb::get_pool_current_epoch<R>(@harvest, st_collection_name) == 4, 0);

        // wait 1/3 of third epoch
        timestamp::update_global_time_for_test_secs(START_TIME + duration * 2 + 120 + 2_000_000);

        // stake 100 from alice
        // stake_lb::stake<R>(&alice_acc, @harvest, coin::withdraw<S>(&alice_acc, amount<S>(100, 0)));
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, amount<S>(100, 0));
        stake_lb::stake<R>(&alice_acc, @harvest, split_token);

        // stake 100 from bob
        let split_token = mint_stake_token(&st_collection_owner, token_data_id, amount<S>(100, 0));
        stake_lb::stake<R>(&bob_acc, @harvest, split_token);
        // stake_lb::stake<R>(&bob_acc, @harvest, coin::withdraw<S>(&bob_acc, amount<S>(100, 0)));

        // wait 2/3 of third epoch
        timestamp::update_global_time_for_test_secs(START_TIME + duration * 2 + 120 + 4_000_000);

        let stake_token = stake_lb::unstake<R>(&bob_acc, @harvest, st_collection_name, bin_id, amount<S>(100, 0));
        token::deposit_token(&alice_acc, stake_token);

        // wait till the end of third epoch and a week more
        timestamp::update_global_time_for_test_secs(START_TIME + duration * 2 + 120 + 6_000_000 + WEEK_IN_SECONDS);

        let stake_token = stake_lb::unstake<R>(&alice_acc, @harvest, st_collection_name, bin_id, amount<S>(100, 0));
        token::deposit_token(&alice_acc, stake_token);

        let alice_rewards = stake_lb::harvest<R>(&alice_acc, @harvest, st_collection_name);
        // as alice were in epoch only 2/3 of time and 1/3 with bob
        // ((1200 / 3) * 0) + ((1200 / 3) * 0.5) + ((1200 / 3) * 1) = 600
        assert!(coin::value(&alice_rewards) == amount<R>(600, 0), 1);
        coin::deposit(@alice, alice_rewards);

        let bob_rewards = stake_lb::harvest<R>(&bob_acc, @harvest, st_collection_name);
        // as bob were in epoch only with alice and 1/3 of epoch time
        // ((1200 / 3) * 0) + ((1200 / 3) * 0.5) + ((1200 / 3) * 0) = 200
        assert!(coin::value(&bob_rewards) == amount<R>(200, 0), 1);
        coin::deposit(@bob, bob_rewards);
    }
}