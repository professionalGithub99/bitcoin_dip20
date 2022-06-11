import HashMap "mo:base/HashMap";
import Nat64 "mo:base/Nat64";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Types "./Types";
import Debug "mo:base/Debug";
import Hash "mo:base/Hash";
import Accounts "./Account";
import Principal "mo:base/Principal";
import List "mo:base/List";
import btc "canister:btc";
import Account "./Account";
import BtcEncryption "../../../tests/BitcoinEncryption";
import Management "../../../tests/management";
import AssocList "mo:base/AssocList";
actor WrappedBitcoin{
  type Account=Accounts.Account;
  let canister_private_key="L5EZftvrYaSudiozVRzTqLcHLNDoVn7H5HSfM9BAN6tMJX8oTWz6";
  func hash_principal(_p:Principal): Hash.Hash{
    return Principal.hash(_p);
  };
  var account_balance_hashmap=HashMap.HashMap<Principal,Nat64>(6,Principal.equal,hash_principal);
  var invoice_hashmap=HashMap.HashMap<Principal,Account>(5,Principal.equal,hash_principal);
  var used_accounts:AssocList.AssocList<Account,Nat64> = List.nil<(Account,Nat64)>();
  var total_supply:Nat64=0;

    public type TxReceipt = {
        #Ok: Nat;
        #Err: {
            #InsufficientAllowance;
            #InsufficientBalance;
            #ErrorOperationStyle;
            #Unauthorized;
            #LedgerTrap;
            #ErrorTo;
            #Other: Text;
            #BlockUsed;
            #AmountTooSmall;
        };
    }; 

//______DIP20 functionality_________
public func mint(to:Principal, value:Nat64):async Nat64{
       let to_balance=_balanceOf(to);
       account_balance_hashmap.put(to,to_balance+value);
       total_supply+=value;
       return to_balance+value;
};

public shared(msg) func send(to:Principal, value:Nat64):async TxReceipt{
    var from_balance = _balanceOf(msg.caller);
    assert(from_balance >= value);
    let to_balance=_balanceOf(to);
    account_balance_hashmap.put(msg.caller,from_balance-value);
    account_balance_hashmap.put(to,to_balance+value);
    return #Ok(Nat64.toNat(to_balance+value));
};
public func totalSupply():async Nat64{
       return total_supply;
};
private func _balanceOf(who: Principal) : Nat64 {
        switch (account_balance_hashmap.get(who)) {
            case (?balance) { return balance; };
            case (_) { return 0; };
        }
    };

//___________BTC functionality_________
  public func generate_private_key():async Text{
    let management_actor= actor("aaaaa-aa"):Management.Self; 
    var rand_priv_key_nat8:[Nat8]= await management_actor.raw_rand();
    var priv_key_wif=BtcEncryption.private_key_to_WIF(rand_priv_key_nat8);
    return priv_key_wif;
  };

   public shared(msg) func create_or_view_current_deposit_invoice():async (Text,Text,Nat64){
        let account=invoice_hashmap.get(msg.caller);
    switch(account){
      case (null){
        var rand_addr=await generate_private_key();
        let a=await Accounts.Account({bitcoin_canister_id=Principal.fromActor(btc)},rand_addr);
        invoice_hashmap.put(msg.caller,a);
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
   public shared(msg) func send_from_invoice(value:Nat64,destination:Text):(){
	let account=invoice_hashmap.get(msg.caller);
    switch(account){
      case (null){
      };
      case (?account){
      var x = account.send(value,destination);
      };
    };
   };

   public shared(msg) func close_invoice():async (Text,Nat64){
   let invoice=invoice_hashmap.get(msg.caller);
   let invoice_balance=await get_balance(msg.caller);
   let a_balance=account_balance_hashmap.get(msg.caller);
   var totals:Nat64=0;
   switch(invoice){
   case(null){
   };
   case(?invoice){
   if(invoice_balance > 0){
      invoice_to_used_accounts(invoice,invoice_balance);
      };
   };
   };
   switch(a_balance){
   case(null){
       var new_balance = mint(msg.caller,invoice_balance);
       totals:=invoice_balance;
      invoice_hashmap.delete(msg.caller);
      return ("You didnt have any initial btc on icp balance here is your first total",totals);
   };
   case(?a_balance){
       var new_balance = mint(msg.caller,invoice_balance);
        totals:=(a_balance+invoice_balance);
      invoice_hashmap.delete(msg.caller);
      return ("btc on icp has now been deposited, your balance is ",totals);
   };
   };
   };

   public func invoice_to_used_accounts(invoice:Account,amount:Nat64){
      used_accounts:=List.push((invoice,amount),used_accounts);
      sort_used_accounts();
   };

   public func sort_used_accounts(){
     var used_acct_arr=List.toArray(used_accounts);
     var sorted_used_acct_arr=Array.sort<(Account,Nat64)>(used_acct_arr,func (a,b){
       Nat64.compare(b.1,a.1);
     });
     used_accounts:=List.fromArray(sorted_used_acct_arr);
   };
   public func print_used_accounts():async [Nat64]{
     var used_acc_arr=List.toArray(used_accounts);
     var used_acc_arr_amt=Array.map<(Account,Nat64),Nat64>(used_acc_arr,func (x){return x.1});
     return used_acc_arr_amt;
   };
   public shared (msg) func unwrap_btc(amount:Nat64,destination:Text):async [Nat64]{
   var leftover_amount:Nat64=amount;
   var replacement_amount:Nat64=0;
   var b:Nat64 = 0;
   var fee:Nat64 = 10000;
    let balance=account_balance_hashmap.get(msg.caller);
    switch(balance){case(null){};case(?balance){b:=balance;};};
    if (b < amount){
    return [];};
      while (List.size(used_accounts) > 0){
        var current=List.get(used_accounts,0);
	switch(current){
	case(null){
	   Debug.trap("somethin wrong");
	   return [];
	};
	case(?current){ 
	  if (current.1 < leftover_amount){
	     leftover_amount-=current.1;
	     used_accounts := List.pop(used_accounts).1;
	     //transfer out current 
	     var send_result= await current.0.send(current.1-fee,destination);
	     total_supply-=current.1;
	  }
	  else{
	   replacement_amount:=current.1-leftover_amount;
	    used_accounts:=List.pop(used_accounts).1;
	    if(current.1 == leftover_amount){
	      //transer out current
	      var send_result= await current.0.send(current.1-fee,destination);
	      total_supply-=current.1;
	    }
	    else{
	       used_accounts:=List.push((current.0,replacement_amount),used_accounts);
	       //transfer out leftover_amount
	       var send_result= await current.0.send(leftover_amount-fee,destination);
	       total_supply-=leftover_amount;
	       sort_used_accounts();
	    };
	   account_balance_hashmap.put(msg.caller,b-amount);
	    return await print_used_accounts();
	  };
	   };
	};
	};
	   account_balance_hashmap.put(msg.caller,b-amount);
	    return await print_used_accounts();
      };

  public shared (msg) func get_account_balance():async (Text,Nat64){
    let balance=account_balance_hashmap.get(msg.caller);
    switch(balance){
      case(null){
        return ("You have no bitcoin on icp balance ",0);
      };
      case(?balance){
        return ("Your total bitcoin on icp balance is ",balance);
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
  public shared(msg) func get_utxos():async Result.Result<Types.GetUtxosData, ?Types.GetUtxosError>{
    let a_balance=invoice_hashmap.get(msg.caller);
    switch(a_balance){
      case(null){
      return #err(null); 
      };
      case(?a_balance){
	let utxos=await a_balance.get_utxos();
	return utxos;
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
    let account = invoice_hashmap.get(_principal);
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
