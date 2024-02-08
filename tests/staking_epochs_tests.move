#[test_only]
module harvest::staking_epochs_tests_move {
    use std::option;

    use aptos_framework::coin;
    use aptos_framework::timestamp;

    use harvest::stake;
    use harvest::stake_test_helpers::{amount, mint_default_coin, StakeCoin as S, RewardCoin as R, new_account_with_stake_coins};
    use harvest::stake_tests::initialize_test;

    // week in seconds, lockup period
    const WEEK_IN_SECONDS: u64 = 604800;

    const START_TIME: u64 = 682981200;

    fun print_epoch(epoch: u64) {
        let (rewards_amount, reward_per_sec, accum_reward, start_time, last_update_time, end_time, distributed, ended_at, is_ghost)
            = stake::get_epoch_info<S, R>(@harvest, epoch);
        std::debug::print(&aptos_std::string_utils::format1(&b"Epoch INFO: {}", epoch));
        std::debug::print(&aptos_std::string_utils::format1(&b"rewards_amount = {}", rewards_amount));
        std::debug::print(&aptos_std::string_utils::format1(&b"reward_per_sec = {}", reward_per_sec));
        std::debug::print(&aptos_std::string_utils::format1(&b"accum_reward = {}", accum_reward));
        std::debug::print(&aptos_std::string_utils::format1(&b"start_time = {}", start_time));
        std::debug::print(&aptos_std::string_utils::format1(&b"last_update_time = {}", last_update_time));
        std::debug::print(&aptos_std::string_utils::format1(&b"end_time = {}", end_time));
        std::debug::print(&aptos_std::string_utils::format1(&b"distributed = {}", distributed));
        std::debug::print(&aptos_std::string_utils::format1(&b"ended_at = {}", ended_at));
        std::debug::print(&aptos_std::string_utils::format1(&b"is_ghost = {}\n", is_ghost));
    }
    fun print_line() {
        std::debug::print(&std::string::utf8(b"============================================================================"));
    }

    // Deposit reward on different epoch stages test
    // todo: what if epoch ended but no user where there

    #[test]
    public fun test_deposit_rew_on_unfinished_rew_epoch() {
        let (harvest, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, amount<S>(100, 0));
        coin::register<R>(&alice_acc);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        let duration = 500;
        stake::register_pool<S, R>(&harvest, reward_coins, duration, option::none());

        // check 0 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward,start_time,
            last_update_time,end_time, distributed, ended_at, is_ghost)
            = stake::get_epoch_info<S, R>(@harvest, 0);
        assert!(rewards_amount == amount<R>(1000, 0), 1);
        assert!(reward_per_sec == amount<R>(2, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME, 1);
        assert!(last_update_time == START_TIME, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == 0, 1);
        assert!(is_ghost == false, 1);

        // stake 100 from alice
        stake::stake<S, R>(&alice_acc, @harvest, coin::withdraw<S>(&alice_acc, amount<S>(100, 0)));

        print_epoch(0);
        print_line();

        // wait half of epoch
        timestamp::update_global_time_for_test_secs(START_TIME + 250);

        // create new epoch, take some rewards from previous
        let reward_coins = mint_default_coin<R>(amount<R>(1000, 0));
        stake::deposit_reward_coins<S, R>(&alice_acc, @harvest, reward_coins, 500);
        let curr_epoch = stake::get_pool_current_epoch<S, R>(@harvest);
        assert!(curr_epoch == 1, 0);

        // check 0 epoch fields
        let (_, _, accum_reward, _, last_update_time,end_time, distributed, ended_at, _)
            = stake::get_epoch_info<S, R>(@harvest, 0);
        assert!(accum_reward == 500_0000_000000, 1);
        assert!(last_update_time == START_TIME + 250, 1);
        assert!(end_time == START_TIME + duration, 1);
        assert!(distributed == amount<R>(500, 0), 1);
        assert!(ended_at == START_TIME + 250, 1);

        // check 1 epoch fields
        let (rewards_amount, reward_per_sec, accum_reward,start_time,
            last_update_time,end_time, distributed, ended_at, is_ghost)
            = stake::get_epoch_info<S, R>(@harvest, 1);
        // 1000 new + 500 from prev epoch
        assert!(rewards_amount == amount<R>(1500, 0), 1);
        assert!(reward_per_sec == amount<R>(3, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(start_time == START_TIME + 250, 1);
        assert!(last_update_time == START_TIME + 250, 1);
        assert!(end_time == START_TIME + 250 + 500, 1);
        assert!(distributed == 0, 1);
        assert!(ended_at == 0, 1);
        assert!(is_ghost == false, 1);

        print_epoch(0);
        print_epoch(1);
        print_line();

        // wait full epoch 1
        timestamp::update_global_time_for_test_secs(START_TIME + 250 + 500);

        // check all rewards was distributed
        let rew = stake::harvest<S, R>(&alice_acc, @harvest);
        assert!(coin::value(&rew) == amount<R>(2000, 0), 1);

        // check 1 epoch fields
        let (_, _, accum_reward, _, last_update_time,end_time, distributed, ended_at, _)
            = stake::get_epoch_info<S, R>(@harvest, 1);
        assert!(accum_reward == 1500_0000_000000, 1);
        assert!(last_update_time == START_TIME + 250 + 500, 1);
        assert!(end_time == START_TIME + 250 + 500, 1);
        assert!(distributed == amount<R>(1500, 0), 1);
        assert!(ended_at == 0, 1);




        coin::deposit(@alice, rew);
    }

    #[test]
    public fun test_rewards_accumulating_after_ghost_epoch() {
        let (harvest, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, amount<S>(100, 0));
        coin::register<R>(&alice_acc);

        // create pool
        let reward_coins = mint_default_coin<R>(amount<R>(157680000, 0));
        let duration = 15768000;
        stake::register_pool<S, R>(&harvest, reward_coins, duration, option::none());

        // stake some coins
        let coins =
            coin::withdraw<S>(&alice_acc, amount<S>(100, 0));
        stake::stake<S, R>(&alice_acc, @harvest, coins);

        // check accum reward
        stake::recalculate_user_stake<S, R>(@harvest, @alice);
        let (_, accum_reward, last_updated, _, _) = stake::get_pool_info<S, R>(@harvest);
        let reward_val = stake::get_pending_user_rewards<S, R>(@harvest, @alice);
        let curr_epoch = stake::get_pool_current_epoch<S, R>(@harvest);
        assert!(reward_val == 0, 1);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME, 1);
        assert!(curr_epoch == 0, 1);

        // wait half of duration & check accum reward
        timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);
        stake::recalculate_user_stake<S, R>(@harvest, @alice);
        let (_, accum_reward, last_updated, _, _) = stake::get_pool_info<S, R>(@harvest);
        let reward_val = stake::get_pending_user_rewards<S, R>(@harvest, @alice);
        let curr_epoch = stake::get_pool_current_epoch<S, R>(@harvest);
        assert!(reward_val == amount<R>(78840000, 0), 1);
        assert!(accum_reward == 788400000000000000, 1);
        assert!(last_updated == START_TIME + duration / 2, 1);
        assert!(curr_epoch == 0, 1);

        // wait full duration & check accum reward
        timestamp::update_global_time_for_test_secs(START_TIME + duration);
        stake::recalculate_user_stake<S, R>(@harvest, @alice);
        let (_, accum_reward, last_updated, _, _) = stake::get_pool_info<S, R>(@harvest);
        let reward_val = stake::get_pending_user_rewards<S, R>(@harvest, @alice);
        let curr_epoch = stake::get_pool_current_epoch<S, R>(@harvest);
        assert!(reward_val == amount<R>(157680000, 0), 1);
        assert!(accum_reward == 1576800000000000000, 1);
        assert!(last_updated == START_TIME + duration, 1);
        assert!(curr_epoch == 0, 1);

        // wait full duration + 1 sec & check accum reward
        timestamp::update_global_time_for_test_secs(START_TIME + duration + 1);
        stake::recalculate_user_stake<S, R>(@harvest, @alice);
        let (_, accum_reward, last_updated, _, _) = stake::get_pool_info<S, R>(@harvest);
        let reward_val = stake::get_pending_user_rewards<S, R>(@harvest, @alice);
        let curr_epoch = stake::get_pool_current_epoch<S, R>(@harvest);
        assert!(reward_val == amount<R>(157680000, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME + duration + 1, 1);
        assert!(curr_epoch == 1, 1);

        // wait full duration + 200 weeks & check accum reward
        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS * 200);
        stake::recalculate_user_stake<S, R>(@harvest, @alice);
        let (_, accum_reward, last_updated, _, _) = stake::get_pool_info<S, R>(@harvest);
        let reward_val = stake::get_pending_user_rewards<S, R>(@harvest, @alice);
        let curr_epoch = stake::get_pool_current_epoch<S, R>(@harvest);
        assert!(reward_val == amount<R>(157680000, 0), 1);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME + duration + WEEK_IN_SECONDS * 200, 1);
        assert!(curr_epoch == 1, 1);

        // check user can get rewards after ghost epoch

        // create new epoch
        let reward_coins = mint_default_coin<R>(amount<R>(150, 0));
        stake::deposit_reward_coins<S, R>(&alice_acc, @harvest, reward_coins, 150);

        // wait full epoch duration & check accum reward
        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS * 200 + 150);
        stake::recalculate_user_stake<S, R>(@harvest, @alice);
        let (_, accum_reward, last_updated, _, _) = stake::get_pool_info<S, R>(@harvest);
        let reward_val = stake::get_pending_user_rewards<S, R>(@harvest, @alice);
        let curr_epoch = stake::get_pool_current_epoch<S, R>(@harvest);
        assert!(reward_val == amount<R>(157680000, 0) + amount<R>(150, 0), 1);
        assert!(accum_reward == 1500000000000, 1);
        assert!(last_updated == START_TIME + duration + WEEK_IN_SECONDS * 200 + 150, 1);
        assert!(curr_epoch == 2, 1);

        let gain = stake::harvest<S, R>(&alice_acc, @harvest);
        assert!(coin::value(&gain) == amount<R>(157680000, 0) + amount<R>(150, 0), 1);
        coin::deposit(@alice, gain);
    }
}
