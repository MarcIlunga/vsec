(* Test EasyCrypt integration *)

let%test_unit "easycrypt_modules_accessible" =
  (* Verify we can access EasyCrypt modules *)
  let _ = EcLib.EcLocation.dummy in
  let _ = EcLib.EcScope.empty in
  let _ = EcLib.EcIdent.create "test" in
  ()

let%test_unit "easycrypt_parser_token_types" =
  (* Verify parser token types are accessible *)
  let open EcLib.EcParser in
  let _ = EOF in
  let _ = IDENT "test" in
  ()

let%test "easycrypt_location_creation" =
  (* Test creating and using locations *)
  let open EcLib.EcLocation in
  let loc = make dummy (0, 0) (0, 5) in
  loc.loc_start = (0, 0) && loc.loc_end = (0, 5)

let%test "easycrypt_ident_operations" =
  (* Test identifier creation and comparison *)
  let open EcLib.EcIdent in
  let id1 = create "foo" in
  let id2 = create "bar" in
  let id3 = create "foo" in
  (* Different names should not be equal *)
  not (equal id1 id2) && 
  (* Same name but different instances should not be equal *)
  not (equal id1 id3)

let%test_unit "easycrypt_path_creation" =
  (* Test path creation *)
  let open EcLib in
  let id = EcIdent.create "test" in
  let path = EcPath.pqname (EcPath.pqoname (EcPath.mpath_abs [] "Test") id.EcIdent.id_symb) in
  ignore path