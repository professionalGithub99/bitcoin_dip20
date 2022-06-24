module {
  public func fromNat(x : Nat) : Text {
    if (x == 0) return "0";
    var ret = "";
    var t = x;
    while (t > 0) {
      ret := (switch (t % 16) {
        case 0 { "0" };
        case 1 { "1" };
        case 2 { "2" };
        case 3 { "3" };
        case 4 { "4" };
        case 5 { "5" };
        case 6 { "6" };
        case 7 { "7" };
        case 8 { "8" };
        case 9 { "9" };
        case 10 { "a" };
        case 11 { "b" };
        case 12 { "c" };
        case 13 { "d" };
        case 14 { "e" };
        case 15 { "f" };
        case _ { "*" };
      }) # ret;
      t /= 16;
    };
    ret
  };
}
