#[test_only]
/// Wrap LB token to coin
module harvest::wrap_token_test {
    // use std::option;

    use std::signer;
    use std::string;
    use aptos_framework::account;
    // use aptos_framework::account;
    use aptos_framework::account::{create_signer_for_test, create_account_for_test};
    use aptos_framework::coin;
    use aptos_framework::genesis;
    // use aptos_framework::resource_account;
    use aptos_framework::timestamp;
    use aptos_token::token;
    use harvest::wrap_token::WStakeCoin;
    use harvest::wrap_token;
    // use liquidswap_v1::bin_steps::X10;
    // use liquidswap_v1::helpers;

    // use harvest::stake::{Self, is_finished};
    // use harvest::stake_config;
    use harvest::stake_test_helpers::{new_account, initialize_reward_coin, initialize_stake_coin};
    // use liquidswap_v1::helpers;
    use liquidswap_v1::helpers::{amount, create_token, create_collection};

    struct W {}
    struct WrapStakeCoin has key {}

    const WEEK_IN_SECONDS: u64 = 604800;

    const START_TIME: u64 = 682981200;

    const X_DECS: u8 = 6;
    const Y_DECS: u8 = 6;
    const ZERO_BIN_ID: u32 = 8388608;

    const ALICE_ADDRESS: address = @0x42;
    const OWNER_ADDRESS: address = @0x43;

    public fun initialize_test(): (signer, signer, signer) {
        genesis::setup();

        timestamp::update_global_time_for_test_secs(START_TIME);

        // let harvest = new_account(@harvest);
        let harvest = create_account_for_test(@harvest);
        let user = new_account(ALICE_ADDRESS);
        // let owner = new_account(OWNER_ADDRESS);
        let collection_owner = new_account(@liquidswap_v1_resource_account);
        // let wrap_token_test = new_account(@wrap_token_test);
        // let wrap_stake_coin_meta = x"0748617276657374010000000000000000403946393837433436313335303337443045324231363339313443444535323030364432414345423135353930464537353135433241353134384538343833324693021f8b08000000000002ff9590c14ec3300c86ef798a29979e68d3762d2b12072e8807e0364dc889cd1ab54da2a42df0f6245a071784b49b7ffbb7ff4f3e3a50039ce9c40c4cb47bdc652fe0570a73c656f2415b937a652e7291b1c59d3d20bd393b6af515075cd9c9c1ace5489cb123207a0a81c289f5972bc9233e49a19250354dd9d03d757b252594884a095577558b15b6250aea5a59b74828e050c39e448d5dd51c90ba741bc99141324a53c89fdc6cc3b38fc41fd60f2776d62929ebe7d98587a288b25f641ee10a48cebb1164d84a653de5d190314f6b5a9a401b43518745a2f6a975714e76a5e2fd1ab2adffe8ec4fa6573b90b9f2f05b78f8c6c3371efecbc3ffe1995360fccf37d1ed0522c8010000010f777261705f7374616b655f636f696e5e1f8b08000000000002ff014700b8ff6d6f64756c6520686172766573743a3a777261705f7374616b655f636f696e207b0a2020202073747275637420575374616b65436f696e3c7068616e746f6d20543e207b7d0a7db1bf1be547000000ab011f8b08000000000002ff8dccbd0a82501880e1efd005143446349850c3590b9a6a0e82c02d480ed11052f6476ddd4150d668435ba182b383086ebab80ae2ace0a257e0f10a7478b79787f92e9a62a6a5d243e6e4bfdefa3cfbd87999d154ebf60eea45690040878692c060e7cbdbdb35da81654b5b4cbc581884de6f34abf9ec3dae5f8f64cf9fce4458f32b71b343004c898da93b2c6cc495ad63ba4d8ab5aa0990036b0ef3abda000000000400000000000000000000000000000000000000000000000000000000000000010e4170746f734672616d65776f726b00000000000000000000000000000000000000000000000000000000000000010b4170746f735374646c696200000000000000000000000000000000000000000000000000000000000000010a4d6f76655374646c696200000000000000000000000000000000000000000000000000000000000000030a4170746f73546f6b656e00";
        // let wrap_stake_coin_code = vector[x"a11ceb0b0600000005010002020206070827082f200a4f0500000001000100010f777261705f7374616b655f636f696e0a575374616b65436f696e0b64756d6d795f6669656c64ecdcba25515e7e94cbba1ddcc0c3926d2d61d0e96b36ded0a83a4e03d9258de9000201020100"];
        // resource_account::create_resource_account_and_publish_package(&harvest, b"harvest_account_seed", wrap_stake_coin_meta, wrap_stake_coin_code);
        let (sig, rs) =
            account::create_resource_account(&harvest, b"harvest_account_seed");
        coin::register<WStakeCoin<WrapStakeCoin>>(&sig);
        coin::register<WrapStakeCoin>(&sig);
        // aptos_framework::code::publish_package_txn(
        //     &harvest,
        //     wrap_stake_coin_meta,
        //     vector[wrap_stake_coin_code]
        // );
        // create coins for pool to be valid
        // initialize_reward_coin(&harvest, 6);
        // initialize_stake_coin(&harvest, 6);
        wrap_token::initialize(&harvest, rs);

        // let emergency_admin = new_account(@stake_emergency_admin);
        // stake_config::initialize(&emergency_admin, @treasury);
        (harvest, user, collection_owner)
    }

    #[test]
    fun test_wrap_lb_token_for_wrap_coin() {
        let (harvest, user, collection_owner) = initialize_test();

        // let (r_s, resource_signer_cap) =
        //     account::create_resource_account(&harvest, b"harvest_account_seed");

        // initialize_x_y_coins(X_DECS, Y_DECS);
        // initialize_x_y_pool<X10>(ZERO_BIN_ID);
        //

        let collection_name = string::utf8(b"Liquidswap v1 #1 \"CX\"-\"CY\"-\"X25\"");
        create_collection(signer::address_of(&collection_owner), collection_name);
        let nft = create_token(&collection_owner, collection_name, string::utf8(b"LB"));
        // let t_id = token::get_token_id(&nft);
        // let td_id = token::get_tokendata_id(t_id);
        let amount = token::get_token_amount(&nft);
        // helpers::deposit_token(ALICE_ADDRESS, nft);

        // nft = token::withdraw_token(&user, t_id, amount);

        wrap_token::wrap_lb_token<WrapStakeCoin>(&user, nft);

        assert!(coin::balance<WrapStakeCoin>(ALICE_ADDRESS) == amount, 1);
    }
}
