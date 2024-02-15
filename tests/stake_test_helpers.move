#[test_only]
module harvest::stake_test_helpers {
    use std::signer;
    use std::string;
    use std::string::{String, utf8};

    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use aptos_token::token;
    use aptos_token::token::{Token, TokenDataId};

    // Coins.

    struct RewardCoin {}

    struct StakeCoin {}

    struct Capabilities<phantom CoinType> has key {
        mint_cap: MintCapability<CoinType>,
        burn_cap: BurnCapability<CoinType>,
    }

    public fun create_stake_token(collection_owner: &signer, collection_name: String, name: String): Token {
        let collection_owner_addr = signer::address_of(collection_owner);

        token::create_token_script(
            collection_owner,
            collection_name,
            name,
            string::utf8(b"Some Description"),
            1,
            10000000000000000000,
            string::utf8(b"https://aptos.dev"),
            collection_owner_addr,
            100,
            0,
            vector<bool>[ false, false, false, false, false, false ],
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
        );
        let token_id = token::create_token_id_raw(
            collection_owner_addr,
            collection_name,
            name,
            0
        );

        token::withdraw_token(collection_owner, token_id, 1)
    }

    public fun mint_token(collection_owner: &signer, token_data_id: TokenDataId, amount: u64) {
        token::mint_token(collection_owner, token_data_id, amount);
    }

    // Stake token collection
    public fun create_st_collection(owner_addr: address, collection_name: String): signer {
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

    public fun initialize_coin<CoinType>(
        admin: &signer,
        name: String,
        symbol: String,
        decimals: u8,
    ) {
        let (b, f, m) = coin::initialize<CoinType>(
            admin,
            name,
            symbol,
            decimals,
            true
        );

        coin::destroy_freeze_cap(f);

        move_to(admin, Capabilities<CoinType> {
            mint_cap: m,
            burn_cap: b,
        });
    }

    public fun initialize_reward_coin(account: &signer, decimals: u8) {
        initialize_coin<RewardCoin>(
            account,
            utf8(b"Reward Coin"),
            utf8(b"RC"),
            decimals
        );
    }

    public fun initialize_stake_coin(account: &signer, decimals: u8) {
        initialize_coin<StakeCoin>(
            account,
            utf8(b"Stake Coin"),
            utf8(b"SC"),
            decimals
        );
    }

    public fun initialize_default_stake_reward_coins(coin_admin: &signer) {
        initialize_stake_coin(coin_admin, 6);
        initialize_reward_coin(coin_admin, 6);
    }

    public fun mint_coin<CoinType>(admin: &signer, amount: u64): Coin<CoinType> acquires Capabilities {
        let admin_addr = signer::address_of(admin);
        let caps = borrow_global<Capabilities<CoinType>>(admin_addr);
        coin::mint(amount, &caps.mint_cap)
    }

    public fun mint_default_coin<CoinType>(amount: u64): Coin<CoinType> acquires Capabilities {
        let caps = borrow_global<Capabilities<CoinType>>(@harvest);
        coin::mint(amount, &caps.mint_cap)
    }

    // Accounts.

    public fun new_account(account_addr: address): signer {
        if (!account::exists_at(account_addr)) {
            account::create_account_for_test(account_addr)
        } else {
            let cap = account::create_test_signer_cap(account_addr);
            account::create_signer_with_capability(&cap)
        }
    }

    public fun new_account_with_stake_coins(account_addr: address, amount: u64): signer acquires Capabilities {
        let account = account::create_account_for_test(account_addr);
        let stake_coins = mint_default_coin<StakeCoin>(amount);
        coin::register<StakeCoin>(&account);
        coin::deposit(account_addr, stake_coins);
        account
    }

    // Math.

    public fun to_u128(num: u64): u128 {
        (num as u128)
    }
}
