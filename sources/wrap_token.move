module harvest::wrap_token {
    use std::option;
    use std::signer;
    use std::string;
    use std::string::{String};
    // use aptos_std::debug::print;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;

    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use aptos_framework::managed_coin;
    use aptos_framework::resource_account;

    use aptos_token::token::{Self, Token, TokenDataId, TokenId};
    // use harvest::wrap_stake_coin;

    /// The contract already initialized.
    const ERR_ALREADY_INITIALIZED: u64 = 0;
    /// When token with zero amount passed as LB token (shouldn't be reached, yet just in case).
    const ERR_LB_TOKEN_ZERO_AMOUNT: u64 = 1;
    /// When provided LB tokens has a wrong creator.
    const ERR_WRONG_TOKEN_CREATOR: u64 = 2;
    /// When provided LB tokens are from wrong token collection.
    const ERR_WRONG_TOKEN_COLLECTION: u64 = 3;
    const ERR_STORE_DOES_NOT_EXIST: u64 = 4;
    /// The signer doesn't have permission to call function.
    const ERR_NO_PERMISSION: u64 = 5;

    struct InitConfiguration has key {
        resource_signer_cap: SignerCapability,
    }

    struct WStakeCoin<phantom T> {}

    struct WSCStore<phantom T> has key {
        token_data_id: TokenDataId,
        token_id: TokenId,
        burn_cap: BurnCapability<WStakeCoin<T>>,
        mint_cap: MintCapability<WStakeCoin<T>>,
    }

    /// Initializing the contract.
    public fun initialize(account: &signer, resource_signer_cap: SignerCapability) {
        let account_addr = signer::address_of(account);
        assert!(account_addr == @harvest, ERR_NO_PERMISSION);

        assert!(!exists<InitConfiguration>(@harvest), ERR_ALREADY_INITIALIZED);

        // let (_, resource_signer_cap) =
        //     account::create_resource_account(account, b"harvest_account_seed");
        // resource_account::create_resource_account(account, b"harvest_account_seed", vector[]);
        // let resource_signer_cap = resource_account::retrieve_resource_account_cap(account, signer::address_of(account));

        move_to(account, InitConfiguration {
            resource_signer_cap,
        });
    }

    public fun wrap_lb_token<T>(user: &signer, asset: Token) acquires WSCStore, InitConfiguration {
        // take token
        let token_amount = token::get_token_amount(&asset);
        assert!(token_amount > 0, ERR_LB_TOKEN_ZERO_AMOUNT);

        let token_id = token::get_token_id(&asset);
        let token_data_id = token::get_tokendata_id(token_id);
        let (token_creator, token_collection, _) =
            token::get_token_data_id_fields(&token_data_id);

        assert!(token_creator == @liquidswap_v1_resource_account, ERR_WRONG_TOKEN_CREATOR);

        let init_config = borrow_global_mut<InitConfiguration>(@harvest);
        let resource_signer =
            account::create_signer_with_capability(&init_config.resource_signer_cap);
        // assert!(account::get_signer_capability_address(&init_config.resource_signer_cap) == @harvest, 1234);
        token::deposit_token(&resource_signer, asset);
        // token::transfer(user, token_id,  @harvest, token_amount);
        let is_store = exists<WSCStore<T>>(@harvest);
        // create or get coin
        if (is_store) {
            check_collection<T>(token_collection);
        } else {
            create_wrap_coin<T>(user, &resource_signer, token_data_id, token_id, token_collection);
        };

        // mint coin
        let mint_cap = &borrow_global<WSCStore<T>>(@harvest).mint_cap;
        let coins = coin::mint<WStakeCoin<T>>(token_amount, mint_cap);

        if (coin::is_account_registered<WStakeCoin<T>>(signer::address_of(user))) {
            coin::register<WStakeCoin<T>>(user);
        };

        coin::deposit(signer::address_of(user), coins)
    }

    fun check_collection<T>(token_collection: String) acquires WSCStore {
        let current_token_id = borrow_global<WSCStore<T>>(@harvest).token_id;
        let current_token_data_id = token::get_tokendata_id(current_token_id);

        let (_, current_token_collection, _) =
            token::get_token_data_id_fields(&current_token_data_id);

        assert!(current_token_collection == token_collection, ERR_WRONG_TOKEN_COLLECTION);
    }

    // fun create_wrap_coin<T>(owner: &signer, token_data_id: TokenDataId, token_id: TokenId, token_collection: String) {
    //     if (!coin::is_account_registered<WStakeCoin<T>>(signer::address_of(owner))) {
    //         managed_coin::register<WStakeCoin<T>>(owner);
    //         // assert!(false, 1111111);
    //     };
    //     let (burn_cap, freeze_cap, mint_cap) =
    //         coin::initialize<WStakeCoin<T>>(
    //             owner, //@harvest
    //             token_collection,
    //             string::utf8(b"WST"),
    //             6,
    //             true
    //         );
    //
    //     // let (burn_cap, freeze_cap, mint_cap) =
    //     //     managed_coin::initialize<WStakeCoin<T>>(
    //     //         owner, //@harvest
    //     //         b"NEW",
    //     //         b"NEW",
    //     //         6,
    //     //         true
    //     //     );
    //     move_to(owner, WSCStore<T> {
    //         //@harvest
    //         token_data_id,
    //         token_id,
    //         burn_cap,
    //         mint_cap
    //     });
    //
    //     coin::destroy_freeze_cap(freeze_cap);
    // }
    fun create_wrap_coin<T>(user: &signer, owner: &signer, token_data_id: TokenDataId, token_id: TokenId, token_collection: String) {
        if (!coin::is_account_registered<WStakeCoin<T>>(signer::address_of(user))) {
            coin::register<WStakeCoin<T>>(user);
            coin::register<WStakeCoin<T>>(owner);
            // assert!(false, 1111111);
        };
        let (burn_cap, freeze_cap, mint_cap) =
            coin::initialize<WStakeCoin<T>>(
                owner, //@harvest
                token_collection,
                string::utf8(b"WST"),
                6,
                true
            );

        // let (burn_cap, freeze_cap, mint_cap) =
        //     managed_coin::initialize<WStakeCoin<T>>(
        //         owner, //@harvest
        //         b"NEW",
        //         b"NEW",
        //         6,
        //         true
        //     );
        move_to(owner, WSCStore<T> {
            //@harvest
            token_data_id,
            token_id,
            burn_cap,
            mint_cap
        });

        coin::destroy_freeze_cap(freeze_cap);
    }

    public fun unwrap_coin<T>(owner: &signer, coins: Coin<WStakeCoin<T>>, to: address) acquires WSCStore {
        assert!(exists<WSCStore<T>>(@harvest), ERR_STORE_DOES_NOT_EXIST);

        let amount = coin::value(&coins);
        let token_id = borrow_global<WSCStore<T>>(@harvest).token_id;
        let burn_cap = &borrow_global<WSCStore<T>>(@harvest).burn_cap;

        coin::burn<WStakeCoin<T>>(coins, burn_cap);
        token::transfer(owner, token_id, to, amount);
    }
}