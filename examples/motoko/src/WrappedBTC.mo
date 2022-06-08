import HashMap "mo:base/HashMap";
import Debug "mo:base/Debug";
import Hash "mo:base/Hash";
import Accounts "./Account";
import Principal "mo:base/Principal";
import List "mo:base/List";
import btc "canister:btc";
import BtcEncryption "../../../tests/BitcoinEncryption";
import Management "../../../tests/management";
actor WrappedBitcoin{
  type Account=Accounts.Account;
  let private_keys=["5JrVA61c5UMKV1hvHo3u1MJrjJhnXwPxQQS77EhH55Ctqh8djw8","L2C1QgyKqNgfV7BpEPAm6PVn2xW8zpXq6MojSbWdH18nGQF2wGsT","5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ",
      "L5EZftvrYaSudiozVRzTqLcHLNDoVn7H5HSfM9BAN6tMJX8oTWz6","Kww4TxWXJBPRDqRihfFnqGVcwRZ8RxWpb5h2ud85Qpvrdh5cpmHs","KxJaFvseWstgLc6qxgaeDoKFCsxx18kg4Gw2CztCAqTuUK5s6rMU","L1QLxPRDiGi6Uvw37GDYGDYeWBWCRDdBwuNJZMYz5nLy7pCoxhbd"];
  var private_key_index=0;
  func hash_principal(_p:Principal): Hash.Hash{
    return Principal.hash(_p);
  };
  let account_balance_hashmap=HashMap.HashMap<Principal,Nat64>(6,Principal.equal,hash_principal);
  let account_hashmap=HashMap.HashMap<Principal,Account>(5,Principal.equal,hash_principal);

  public func generate_private_key():async Text{
    let management_actor= actor("aaaaa-aa"):Management.Self; 
    var rand_priv_key_nat8:[Nat8]= await management_actor.raw_rand();
    var priv_key_wif=BtcEncryption.private_key_to_WIF(rand_priv_key_nat8);
    return priv_key_wif;
  };

   public shared(msg) func create_or_view_current_deposit_invoice():async (Text,Text,Nat64){
        let account=account_hashmap.get(msg.caller);
    switch(account){
      case (null){
        var rand_addr=await generate_private_key();
        //private_key_index:=private_key_index+1;
        //let a=await Accounts.Account({bitcoin_canister_id=Principal.fromActor(btc)},private_keys[private_key_index-1]);
        let a=await Accounts.Account({bitcoin_canister_id=Principal.fromActor(btc)},rand_addr);
        account_hashmap.put(msg.caller,a);
        let acc_address=await a.btc_address();
        let acc_balance=await get_balance(msg.caller);
        return ("You did not have an invoice open please deposit to this address ",acc_address,acc_balance);
      };
      case (?account){
        let acc_address=await account.btc_address();
        let balance=await get_balance(msg.caller);
        return ("you have an address open feel free to deposit more to this address",acc_address,balance);
      };
    };
   };

   public shared(msg) func close_invoice():async (Text,Nat64){
   let invoice=account_hashmap.get(msg.caller);
   let invoice_balance=await get_balance(msg.caller);
   let a_balance=account_balance_hashmap.get(msg.caller);
   var totals:Nat64=0;
   switch(a_balance){
   case(null){
       account_balance_hashmap.put(msg.caller,invoice_balance);
       totals:=invoice_balance;
      account_hashmap.delete(msg.caller);
      return ("You didnt have an invoice open but heres your wrapped bitcoin balance ",totals);
   };
   case(?a_balance){
       account_balance_hashmap.put(msg.caller,(a_balance+invoice_balance));
        totals:=(a_balance+invoice_balance);
      account_hashmap.delete(msg.caller);
      return ("Bitcoin has now been wrapped, your balance is ",totals);
   };
   };
   };

  public shared (msg) func get_account_balance():async (Text,Nat64){
    let balance=account_balance_hashmap.get(msg.caller);
    switch(balance){
      case(null){
        return ("You have no wrapped bitcoin balance ",0);
      };
      case(?balance){
        return ("Your total wrapped bitcoin balance is ",balance);
      };
    };
  };
  public shared(msg) func send_btc(_wif_private_key:Text,_amount:Nat64,_to_address:Text):async (Text,Nat64){
        let a=await Accounts.Account({bitcoin_canister_id=Principal.fromActor(btc)},_wif_private_key);
        var x=await a.send(_amount,_to_address);
        var balance= await a.balance();
        switch(balance){
          case(#ok(satoshi)){
            return ("the balance is ",satoshi);
          };
          case(#err(satoshi_error)){
            Debug.trap("satoshi_error");
          };
  };
  };
  public shared(msg) func get_address_balance(_wif_private_key:Text):async (Text,Nat64){
        let a=await Accounts.Account({bitcoin_canister_id=Principal.fromActor(btc)},_wif_private_key);
        var balance= await a.balance();
        switch(balance){
          case(#ok(satoshi)){
            return ("the balance is ",satoshi);
          };
          case(#err(satoshi_error)){
            Debug.trap("satoshi_error");
          };
  };
  };

  public shared func get_balance(_principal:Principal):async Nat64{
    let account = account_hashmap.get(_principal);
    switch(account){
      case (null){
        return 0;
      };
      case (?account){
        let balance=await account.balance();
        switch(balance){
          case(#ok(satoshi)){
            return satoshi;
          };
          case(#err(satoshi_error)){
            Debug.trap("satoshi_error");
          };
        };
      };
    };
  };
}
