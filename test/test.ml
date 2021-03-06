open OUnit
open Ulib

(* Helpers *)

let try_chr n = try Some (UChar.chr n) with Out_of_range -> None

let sgn n = if n < 0 then -1 else if n = 0 then 0 else 1

let rec range i j = 
  if i > j then [] else
  i :: range (i + 1) j

(* Tests for UChar *)

let test_char1 () =
  for i = 0 to 255 do
    let c = Char.chr i in
    let c' = UChar.char_of (UChar.of_char c) in
    assert_equal c c'
  done

let test_char2 () =
  for i = 0 to 10000 do
    let n = Random.bits () in
    match try_chr n with
      None -> ()
    | Some u ->
	if n < 255 then
	  assert_equal (UChar.char_of u) (Char.chr n)
	else
	  assert_raises Out_of_range (fun () -> UChar.char_of u)
  done

let test_uchar_eq () =
  assert_equal true (UChar.eq (UChar.of_char 'a') (UChar.of_char 'a'));
  assert_equal true (UChar.eq (UChar.chr 0xffff) (UChar.chr 0xffff));
  assert_equal false(UChar.eq (UChar.chr 0xffff) (UChar.chr 0xfffe))

let test_int_uchar () =
  for i = 0 to 10000 do
    let n = Random.bits () in
    if n < 0xd800 then
      assert_equal n (UChar.code (UChar.chr n))
    else if n < 0xe000 then
      assert_raises Out_of_range (fun () -> (UChar.chr n))
    else if n <= 0x10ffff then
	assert_equal n (UChar.code (UChar.chr n))
    else
      assert_raises Out_of_range (fun () -> (UChar.chr n))
  done	

let test_uchar_compare () =
  for i = 0 to 10000 do
    let n1 = Random.bits () in
    let n2 = Random.bits () in
    match try_chr n1, try_chr n2 with
    Some u1, Some u2 -> 
      assert_equal (sgn (compare n1 n2)) (sgn (UChar.compare u1 u2))
    | _ -> ()
  done

(* UTF-8 *)

let rec random_uchar () = 
  match try_chr (Random.bits ()) with
    Some u -> u
  | None -> random_uchar ()

let test_utf8_random () =
  for i = 0 to 10 do
    let a = Array.init (Random.int 1000) (fun _ -> random_uchar ()) in
    let s = UTF8.init (Array.length a) (Array.get a) in

    (* test for length *)
    let len = UTF8.length s in
    assert_equal len (Array.length a);

    (* indexing *)
    for i = 0 to Array.length a - 1 do
      assert_equal (UTF8.get s i) a.(i)
    done;
    
    (* iteration *)
    let r = ref 0 in
    UTF8.iter (fun u ->
      assert_equal u a.(!r);
      incr r) s;
    assert_equal !r len;
    
    (* index *)
    let cur = ref (UTF8.nth s 0) in
    let r = ref 0 in
    while not (UTF8.out_of_range s !cur) do
      assert_equal (UTF8.look s !cur) a.(!r);
      cur := UTF8.next s !cur;
      incr r
    done;
    assert_equal !r len;
    
    (* Moving index around *)
    for i = 0 to 100 do
      let pos = Random.int len in
      let cur = UTF8.nth s pos in
      assert_equal (UTF8.look s cur) a.(pos);
      
      if pos = 0 then () else
      let cur' = UTF8.prev s cur in
      assert_equal (UTF8.look s cur') a.(pos - 1);
    done;
      
      (* Buffer *)
    let b = UTF8.Buf.create 0 in
    
    let p = Random.int len in
    let s1 = UTF8.init p (Array.get a) in
    let s2 = UTF8.init (len - p) (fun x -> Array.get a (p + x)) in
    
    UTF8.Buf.add_string b s1;
    UTF8.Buf.add_string b s2;
    let s' = UTF8.Buf.contents b in
    assert_bool "step1" (UTF8.compare s s' = 0);
    
    UTF8.Buf.clear b;
    UTF8.iter (UTF8.Buf.add_char b) s;
    let s' = UTF8.Buf.contents b in
    assert_bool "step2" (UTF8.compare s s' = 0);
    
    UTF8.Buf.clear b;
    let b' = UTF8.Buf.create 16 in
    let pos = Random.int len in
    for i = 0 to len - 1 do
      if i < pos then
	UTF8.Buf.add_char b a.(i)
      else
	UTF8.Buf.add_char b' a.(i)
    done;
    UTF8.Buf.add_buffer b b';
    let s' = UTF8.Buf.contents b in
    assert_bool "step3" (UTF8.compare s s' = 0);
    
    UTF8.Buf.reset b;
    UTF8.Buf.add_string b s;
    let s' = UTF8.Buf.contents b in
    assert_bool "step4" (UTF8.compare s s' = 0)
  done


(* stress test *) 
let random_string () =
  let s = String.create (Random.int 1000) in
  for i = 0 to String.length s - 1 do
    s.[i] <- Char.chr (Random.int 256)
  done;
  s

let test_utf8_random_string () =
  for i = 0 to 100 do
    let s = random_string () in
    match (try UTF8.validate s; Some s with Malformed_code -> None) with
      None -> ()
    | Some s ->
	let cur = ref (UTF8.nth s 0) in
	let r = ref 0 in
	while not (UTF8.out_of_range s !cur) do
	  ignore(UTF8.look s !cur);
	  cur := UTF8.next s !cur;
	  incr r
	done;
	assert_equal !cur (String.length s);
	assert_equal !r (UTF8.length s)
  done
	

(* Test based on "UTF-8 decoder capability and stress test" by
    Markus Kuhn <http://www.cl.cam.ac.uk/~mgk25/> - 2003-02-19 *)

let test_utf8_valid_utf8_string (name, s, clist) =
  let test () =
    assert_equal (UTF8.validate s) ();
    let last = 
      List.fold_left (fun i n ->
	let u = UTF8.look s i in
	assert_equal ~msg:(Printf.sprintf "character %x != %x" n (UChar.code u)) u  (UChar.chr n);
	UTF8.next s i) 0 clist
    in
    assert_equal ~msg:"length" last (String.length s) in
  ("valid string: " ^ name) >:: test

  
let utf8_valid_pairs =
  [
   (* Greek word*)
   ("kosme", "κόσμε", [0x03BA; 0x1f79; 0x03C3; 0x03BC; 0x03B5]);

   (* Boundary cases *)
   ("NULL", " ", [0x00]);
   ("0x80", "", [0x0080]);
   ("0x800", "ࠀ", [0x800]);
   ("0x10000", "𐀀", [0x00010000]);
   ("0x7F", "", [0x0000007F]);
   ("0x7FF", "߿", [0x07FF]);
   ("0xFFFF", "￿", [0xFFFF]);
   ("0xD7FF", "퟿", [0xD7FF]);
   ("0xE000", "",[0xE000]);
   ("0xFFFD", "�", [0xFFFD]);
   ("0x10FFFF", "􏿿", [0x10FFFF]);
 ]

let test_utf8_invalid_utf8_string s =
  ("invalid string:" ^ (String.escaped s)) >:: (fun () -> assert_raises Malformed_code (fun () -> UTF8.validate s))

let utf8_brokens =
  [
   (* Continuation byte *)
   "�"; "�"; "��"; "���"; "����"; "�����";
   "������"; "�������";
   "����������������\
    ����������������\
    ����������������\
    ����������������";

   (* Lonley start characters *)
   "� � � � � � � � � � � � � � � � \
    � � � � � � � � � � � � � � � � ";
   "� � � � � � � � � � � � � � � � ";
   "� � � � � � � � ";
   "� � � � ";
   "� � ";

   (* Missing last byte *)
   "�";
   "��";
   "���";
   "����";
   "�����";
   "�";
   "�";
   "���";
   "����";
   "�����";
   "�����������������������������";

   (* Impossible bytes *)
   "�";
   "�";
   "����";

   (* Overlong sequences *)
   "��";
   "���";
   "����";
   "�����";
   "������";

   "��";
   "���";
   "����";
   "�����";
   "������";

   "��";
   "���";
   "����";
   "�����";
   "������";
   
   (* illegal code point *)
   (* out of range *)
   "����";
   "������";

   (* surrogates *)
   "���";
   "���";
   "���";
   "���";
   "���";
   "���";
   "���";

   "������";
   "������";
   "������";
   "������";
   "������";
   "������";
   "������";  
   "������";

(*   "￾";
   "￿" *)
 ]
  


(* Text *)

let test_text_random () =
  for i = 0 to 10 do
    let a = Array.init (Random.int 1000) (fun _ -> random_uchar ()) in
    let s = Text.init (Array.length a) (Array.get a) in

    (* test for length *)
    let len = Text.length s in
    assert_equal len (Array.length a);

    (* indexing *)
    for i = 0 to Array.length a - 1 do
      assert_equal (Text.get s i) a.(i)
    done;
    
    (* iteration *)
    let r = ref 0 in
    Text.iter (fun u ->
      assert_equal u a.(!r);
      incr r) s;
    assert_equal !r len;
  done


(* stress test *) 
let test_text_random_string () =
  for i = 0 to 100 do
    assert_equal () 
      (let s = random_string () in
      match (try Some (Text.of_string s) with Malformed_code -> None) with
	None -> ()
      | Some text ->
	  for i = 0 to Text.length text - 1 do
	    ignore(Text.get text i)
	  done)
  done
	

(* Test based on "UTF-8 decoder capability and stress test" by
    Markus Kuhn <http://www.cl.cam.ac.uk/~mgk25/> - 2003-02-19 *)

let test_text_valid_utf8_string (name, s, clist) =
  let test () =
    let text = Text.of_string s in
    for i = 0 to List.length clist - 1 do
      let u = Text.get text i in
      let n = List.nth clist i in
      assert_equal ~msg:(Printf.sprintf "character %x != %x" n (UChar.code u)) u  (UChar.chr n);      
    done;
  in
  ("valid string: " ^ name) >:: test


let test_text_invalid_utf8_string s =
  ("invalid string:" ^ (String.escaped s)) >:: (fun () -> assert_raises Malformed_code (fun () -> Text.of_string s))


let suite = 
  "ulib test" >:::
  ["test UChar" >:::
   ["chr<->uchar" >:::
    ["uchar<-char" >:: test_char1;
     "char<-uchar" >:: test_char2];
    "uchar<->code" >:: test_int_uchar;
    "test_uchar_eq" >:: test_uchar_eq;
    "test_uchar_compare" >:: test_uchar_compare];
   "test UTF8" >::: 
   ["random test" >:: test_utf8_random;
    "random string test" >:: test_utf8_random_string;
    "valid strings" >::: (List.map test_utf8_valid_utf8_string utf8_valid_pairs);
    "invalid strings" >::: (List.map test_utf8_invalid_utf8_string utf8_brokens)];
   "test Text" >::: 
   ["random test" >:: test_text_random;
    "random string test" >:: test_text_random_string;
    "valid strings" >::: (List.map test_text_valid_utf8_string utf8_valid_pairs);
    "invalid strings" >::: (List.map test_text_invalid_utf8_string utf8_brokens)]]

let _ = 
  run_test_tt_main suite

