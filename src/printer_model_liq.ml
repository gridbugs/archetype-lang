open Location
open Tools
open Model
open Printer_tools

exception Anomaly of string

type error_desc =
  | UnsupportedBreak
  | UnsupportedTerm of string
[@@deriving show {with_path = false}]

let emit_error (desc : error_desc) =
  let str = Format.asprintf "%a@." pp_error_desc desc in
  raise (Anomaly str)

type operator =
  | Equal
  | Nequal
  | Lt
  | Le
  | Gt
  | Ge
  | Plus
  | Minus
  | Mult
  | Div
  | Modulo

type position =
  | Lhs
  | Rhs

let pp_cast (pos : position) (ltype : type_) (rtype : type_) (pp : 'a -> mterm -> unit) (fmt : Format.formatter) =
  match pos, ltype, rtype with
  | Lhs, Tbuiltin Brole, Tbuiltin Baddress ->
    Format.fprintf fmt "(%a : address)" pp
  | Rhs, Tbuiltin Baddress, Tbuiltin Brole ->
    Format.fprintf fmt "(%a : address)" pp
  | _ -> pp fmt

let pp_str fmt str =
  Format.fprintf fmt "%s" str

let to_lident = dumloc

let pp_nothing (fmt : Format.formatter) = ()

let pp_model fmt (model : model) =

  let pp_model_name (fmt : Format.formatter) _ =
    Format.fprintf fmt "(* contract: %a *)"
      pp_id model.name
  in

  let pp_currency fmt = function
    | Tez   -> Format.fprintf fmt "tz"
    | Mutez -> Format.fprintf fmt "mtz"
  in

  let pp_btyp fmt = function
    | Bbool       -> Format.fprintf fmt "bool"
    | Bint        -> Format.fprintf fmt "int"
    | Brational   -> Format.fprintf fmt "rational"
    | Bdate       -> Format.fprintf fmt "timestamp"
    | Bduration   -> Format.fprintf fmt "duration"
    | Bstring     -> Format.fprintf fmt "string"
    | Baddress    -> Format.fprintf fmt "address"
    | Brole       -> Format.fprintf fmt "key_hash"
    | Bcurrency c -> pp_currency fmt c
    | Bkey        -> Format.fprintf fmt "key"
  in

  let pp_container fmt = function
    | Collection -> Format.fprintf fmt "list"
    | Partition  -> Format.fprintf fmt "list"
  in

  let rec pp_type fmt t =
    match t with
    | Tasset an ->
      Format.fprintf fmt "%a" pp_id an
    | Tenum en ->
      Format.fprintf fmt "%a" pp_id en
    | Tcontract cn ->
      Format.fprintf fmt "%a" pp_id cn
    | Tbuiltin b -> pp_btyp fmt b
    | Tcontainer (t, c) ->
      Format.fprintf fmt "%a %a"
        pp_type t
        pp_container c
    | Toption t ->
      Format.fprintf fmt "%a option"
        pp_type t
    | Ttuple ts ->
      Format.fprintf fmt "%a"
        (pp_list " * " pp_type) ts
    | Tunit ->
      Format.fprintf fmt "unit"
    | Tstorage ->
      Format.fprintf fmt "storage"
    | Toperation ->
      Format.fprintf fmt "operation"
    | Tentry ->
      Format.fprintf fmt "entry"
    | Tprog _
    | Tvset _
    | Ttrace _ -> Format.fprintf fmt "todo"
  in


  let pp_storage_const fmt = function
    | Get an ->
      let _, t = Utils.get_record_key model (to_lident an) in
      Format.fprintf fmt
        "let[@inline] get_%s (s, key : storage * %a) : %s =@\n  \
         match Map.find key s.%s_assets with@\n  \
         | Some v -> v@\n  \
         | _ -> failwith \"not_found\"@\n"
        an pp_btyp t an an
    | Set an ->
      let _, t = Utils.get_record_key model (to_lident an) in
      Format.fprintf fmt
        "let[@inline] set_%s (s, key, asset : storage * %a * %s) : storage =@\n  \
         s.%s_assets <- Map.update key (Some asset) s.%s_assets@\n"
        an pp_btyp t an an an

    | Add an ->
      let k, t = Utils.get_record_key model (to_lident an) in
      Format.fprintf fmt
        "let[@inline] add_%s (s, asset : storage * %s) : storage =@\n  \
         let key = asset.%s in@\n  \
         let s = s.%s_keys <- add_list key s.%s_keys in@\n  \
         s.%s_assets <- Map.update key (Some asset) s.%s_assets@\n"
        an an (unloc k) an an an an

    | Remove an ->
      let _, t = Utils.get_record_key model (to_lident an) in
      Format.fprintf fmt
        "let[@inline] remove_%s (s, key : storage * %a) : storage =@\n  \
         let s = s.%s_keys <- remove_list key s.%s_keys in@\n  \
         s.%s_assets <- Map.update key None s.%s_assets@\n"
        an pp_btyp t an an an an

    | Clear an ->
      let k, t = Utils.get_record_key model (to_lident an) in
      Format.fprintf fmt
        "let[@inline] clear_%s (s : storage) : storage =@\n  \
         let s = s.%s_keys <- [] in@\n  \
         s.%s_assets <- (%a, %s) map@\n"
        an an an pp_btyp t an

    | Reverse an ->
      Format.fprintf fmt
        "let[@inline] reverse_%s (s : storage) : storage =@\n  \
         s.%s_keys <- List.rev s.%s_keys@\n"
        an an an

    | UpdateAdd (an, fn) ->
      let k, t = Utils.get_record_key model (to_lident an) in
      let ft, c = Utils.get_field_container model an fn in
      let kk, _ = Utils.get_record_key model (to_lident ft) in
      Format.fprintf fmt
        "let[@inline] add_%s_%s (s, a, b : storage * %s * %s) : storage =@\n  \
         let asset = a.%s <- add_list b.%a a.%s in@\n  \
         s.%s_assets <- Map.update a.%a (Some asset) s.%s_assets@\n"
        an fn an ft
        fn pp_id kk fn
        an pp_id k an

    | UpdateRemove (an, fn) ->
      let k, t = Utils.get_record_key model (to_lident an) in
      let ft, c = Utils.get_field_container model an fn in
      let kk, tt = Utils.get_record_key model (to_lident ft) in
      Format.fprintf fmt
        "let[@inline] remove_%s_%s (s, a, key : storage * %s * %a) : storage =@\n  \
         let asset = a.%s <- remove_list key a.%s in@\n  \
         s.%s_assets <- Map.update a.%a (Some asset) s.%s_assets@\n"
        an fn an pp_btyp tt
        fn fn
        an pp_id k an

    | UpdateClear (an, fn) ->
      Format.fprintf fmt
        "let[@inline] clear_%s_%s (s : storage * %s) : storage =@\n  \
         s (*TODO*)@\n"
        an fn an

    | UpdateReverse (an, fn) ->
      Format.fprintf fmt
        "let[@inline] reverse_%s_%s (s : storage * %s) : storage =@\n  \
         s (*TODO*)@\n"
        an fn an

    | ToKeys an ->
      Format.fprintf fmt
        "let[@inline] to_keys_%s (s : storage) : storage =@\n  \
         s (*TODO*)@\n"
        an
  in

  let pp_container_const fmt = function
    | Add t-> Format.fprintf fmt "add\t %a" pp_type t
    | Remove t -> Format.fprintf fmt "remove\t %a" pp_type t
    | Clear t -> Format.fprintf fmt "clear\t %a" pp_type t
    | Reverse t -> Format.fprintf fmt "reverse %a" pp_type t
  in

  let pp_function_const fmt = function
    | Select an ->
      let _, t = Utils.get_record_key model (to_lident an) in
      Format.fprintf fmt
        "let[@inline] select_%s (s, c, p : storage * %a list * (%s -> bool)) : %s list =@\n  \
         List.fold (fun (x, accu) ->@\n  \
         let a = get_%s (s, x) in@\n  \
         if p a@\n  \
         then add_list a accu@\n  \
         else accu@\n  \
         ) c []@\n"
        an pp_btyp t an an
        an

    | Sort (an, fn) ->
      Format.fprintf fmt
        "let[@inline] sort_%s_%s (s : storage) : unit =@\n  \
         () (*TODO*)@\n"
        an fn

    | Contains an ->
      let _, t = Utils.get_record_key model (to_lident an) in
      Format.fprintf fmt
        "let[@inline] contains_%s ((l, key) : %a list * %a) : bool =@\n  \
         List.fold (fun (x, accu) ->@\n    \
         accu || x = key@\n  \
         ) l false@\n"
        an
        pp_btyp t
        pp_btyp t

    | Nth an ->
      Format.fprintf fmt
        "let[@inline] nth_%s (s : storage) : unit =@\n  \
         () (*TODO*)@\n"
        an

    | Count an ->
      Format.fprintf fmt
        "let[@inline] count_%s (s : storage) : unit =@\n  \
         () (*TODO*)@\n"
        an

    | Sum (an, fn) ->
      let show_zero = function
        | _ -> "0"
      in
      let record_item = Utils.get_record_field model (dumloc an, dumloc fn) in
      let t = record_item.type_ in
      Format.fprintf fmt
        "let[@inline] sum_%s_%s (s : storage) : %a =@\n  \
         Map.fold (fun (x, accu) ->@\n  \
         accu + x.(1).%s@\n  \
         ) s.%s_assets %s@\n"
        an fn pp_type t fn an (show_zero t)

    | Min (an, fn) ->
      Format.fprintf fmt
        "let[@inline] min_%s_%s (s : storage) : unit =@\n  \
         () (*TODO*)@\n"
        an fn

    | Max (an, fn) ->
      Format.fprintf fmt
        "let[@inline] max_%s_%s (s : storage) : unit =@\n  \
         () (*TODO*)@\n"
        an fn

  in

  let pp_builtin_const fmt = function
    | Min t-> Format.fprintf fmt "min on %a" pp_type t
    | Max t-> Format.fprintf fmt "max on %a" pp_type t
  in

  let pp_api_item_node fmt = function
    | APIStorage   v -> pp_storage_const fmt v
    | APIContainer v -> pp_container_const fmt v
    | APIFunction  v -> pp_function_const fmt v
    | APIBuiltin   v -> pp_builtin_const fmt v
  in


  let pp_utils fmt l =
    let pp_util_add fmt _ =
      Format.fprintf fmt
        "@\nlet add_list elt l = List.rev (elt::(List.rev l))@\n"
    in

    let pp_util_remove fmt _ =
      Format.fprintf fmt
        "@\nlet remove_list elt l =@\n  \
         List.fold (fun (x, accu) ->@\n  \
         if x = elt@\n  \
         then accu@\n  \
         else add_list elt accu@\n  \
         ) [] l@\n"
    in

    let ga, gr = List.fold_left (fun (ga, gr) (x : api_item) ->
        match x.node with
        | APIStorage   (Get           _) -> (ga, gr)
        | APIStorage   (Set           _) -> (ga, gr)
        | APIStorage   (Add           _) -> (true, gr)
        | APIStorage   (Remove        _) -> (true, true)
        | APIStorage   (Clear         _) -> (ga, gr)
        | APIStorage   (Reverse       _) -> (ga, gr)
        | APIStorage   (UpdateAdd     _) -> (true, gr)
        | APIStorage   (UpdateRemove  _) -> (true, true)
        | APIStorage   (UpdateClear   _) -> (ga, gr)
        | APIStorage   (UpdateReverse _) -> (ga, gr)
        | APIStorage   (ToKeys        _) -> (ga, gr)
        | APIFunction  (Select        _) -> (ga, gr)
        | APIFunction  (Sort          _) -> (ga, gr)
        | APIFunction  (Contains      _) -> (ga, gr)
        | APIFunction  (Nth           _) -> (ga, gr)
        | APIFunction  (Count         _) -> (ga, gr)
        | APIFunction  (Sum           _) -> (ga, gr)
        | APIFunction  (Min           _) -> (ga, gr)
        | APIFunction  (Max           _) -> (ga, gr)
        | APIContainer (Add           _) -> (ga, gr)
        | APIContainer (Remove        _) -> (ga, gr)
        | APIContainer (Clear         _) -> (ga, gr)
        | APIContainer (Reverse       _) -> (ga, gr)
        | APIBuiltin   (Min           _) -> (ga, gr)
        | APIBuiltin   (Max           _) -> (ga, gr)
      )   (false, false) l in
    if   ga || gr
    then
      Format.fprintf fmt "(* Utils *)@\n%a%a@\n"
        pp_util_add ()
        (pp_do_if gr pp_util_remove) ()

  in

  let pp_api_item fmt (api_item : api_item) =
    if api_item.only_formula
    then ()
    else pp_api_item_node fmt api_item.node
  in

  let pp_api_items fmt l =
    if List.is_empty l
    then pp_nothing fmt
    else
      Format.fprintf fmt "(* API function *)%a@\n"
        (pp_list "@\n" pp_api_item) l
  in

  let pp_operator fmt op =
    let to_str = function
      | ValueAssign -> ":="
      | PlusAssign -> "+="
      | MinusAssign -> "-="
      | MultAssign -> "*="
      | DivAssign -> "/="
      | AndAssign -> "&="
      | OrAssign -> "|="
    in
    pp_str fmt (to_str op)
  in

  let rec pp_qualid fmt (q : qualid) =
    match q.node with
    | Qdot (q, i) ->
      Format.fprintf fmt "%a.%a"
        pp_qualid q
        pp_id i
    | Qident i -> pp_id fmt i
  in

  let pp_pattern fmt (p : pattern) =
    match p.node with
    | Pconst i -> pp_id fmt i
    | Pwild -> pp_str fmt "_"
  in

  let pp_mterm fmt (mt : mterm) =
    let rec f fmt (mtt : mterm) =
      match mtt.node with
      | Mif (c, t, None) ->
        Format.fprintf fmt "@[if %a@ then %a@]"
          f c
          f t

      | Mif (c, t, Some e) ->
        Format.fprintf fmt "@[if %a then @\n  @[%a @]@\nelse @\n  @[%a @]@]"
          f c
          f t
          f e

      | Mmatchwith (e, l) ->
        let pp fmt (e, l) =
          Format.fprintf fmt "match %a with@\n@[<v 2>%a@]"
            f e
            (pp_list "@\n" (fun fmt (p, x) ->
                 Format.fprintf fmt "| %a -> %a"
                   pp_pattern p
                   f x
               )) l
        in
        pp fmt (e, l)

      | Mapp (e, args) ->
        let pp fmt (e, args) =
          Format.fprintf fmt "%a (%a)"
            pp_id e
            (pp_list ", " f) args
        in
        pp fmt (e, args)

      | Mexternal (_, _, c, args) ->
        let pp fmt (c, args) =
          Format.fprintf fmt "%a (%a)"
            f c
            (pp_list ", " f) args
        in
        pp fmt (c, args)

      | Mget (c, k) ->
        let pp fmt (c, k) =
          Format.fprintf fmt "get_%a (_s, %a)"
            pp_str c
            f k
        in
        pp fmt (c, k)

      | Mset (c, k, v) ->
        let pp fmt (c, k, v) =
          Format.fprintf fmt "set_%a (_s, %a, %a)"
            pp_str c
            f k
            f v
        in
        pp fmt (c, k, v)

      | Maddasset (an, i) ->
        let pp fmt (an, i) =
          Format.fprintf fmt "add_%a (_s, %a)"
            pp_str an
            f i
        in
        pp fmt (an, i)

      | Maddfield (an, fn, c, i) ->
        let pp fmt (an, fn, c, i) =
          Format.fprintf fmt "add_%a_%a (_s, %a, %a)"
            pp_str an
            pp_str fn
            f c
            f i
        in
        pp fmt (an, fn, c, i)

      | Maddlocal (c, i) ->
        let pp fmt (c, i) =
          Format.fprintf fmt "add (%a, %a)"
            f c
            f i
        in
        pp fmt (c, i)

      | Mremoveasset (an, i) ->
        let cond, str =
          (match i.type_ with
           | Tasset an ->
             let k, _ = Utils.get_record_key model an in
             true, "." ^ (unloc k)
           | _ -> false, ""
          ) in
        let pp fmt (an, i) =
          Format.fprintf fmt "remove_%a (_s, %a%a)"
            pp_str an
            f i
            (pp_do_if cond pp_str) str
        in
        pp fmt (an, i)

      | Mremovefield (an, fn, c, i) ->
        let cond, str =
          (match i.type_ with
           | Tasset an ->
             let k, _ = Utils.get_record_key model an in
             true, "." ^ (unloc k)
           | _ -> false, ""
          ) in
        let pp fmt (an, fn, c, i) =
          Format.fprintf fmt "remove_%a_%a (_s, %a, %a%a)"
            pp_str an
            pp_str fn
            f c
            f i
            (pp_do_if cond pp_str) str
        in
        pp fmt (an, fn, c, i)

      | Mremovelocal (c, i) ->
        let pp fmt (c, i) =
          Format.fprintf fmt "remove (%a, %a)"
            f c
            f i
        in
        pp fmt (c, i)

      | Mclearasset (an) ->
        let pp fmt (an) =
          Format.fprintf fmt "clear_%a (_s)"
            pp_str an
        in
        pp fmt (an)

      | Mclearfield (an, fn, i) ->
        let pp fmt (an, fn, i) =
          Format.fprintf fmt "clear_%a_%a (_s, %a)"
            pp_str an
            pp_str fn
            f i
        in
        pp fmt (an, fn, i)

      | Mclearlocal (i) ->
        let pp fmt (i) =
          Format.fprintf fmt "clear (%a)"
            f i
        in
        pp fmt (i)

      | Mreverseasset (an) ->
        let pp fmt (an) =
          Format.fprintf fmt "reverse_%a (_s)"
            pp_str an
        in
        pp fmt (an)

      | Mreversefield (an, fn, i) ->
        let pp fmt (an, fn, i) =
          Format.fprintf fmt "reverse_%a_%a (_s, %a)"
            pp_str an
            pp_str fn
            f i
        in
        pp fmt (an, fn, i)

      | Mreverselocal (i) ->
        let pp fmt (i) =
          Format.fprintf fmt "reverse (%a)"
            f i
        in
        pp fmt (i)

      | Mselect (an, c, p) ->
        let pp fmt (an, c, p) =
          Format.fprintf fmt "select_%a (_s, %a, fun the -> %a)"
            pp_str an
            f c
            f p
        in
        pp fmt (an, c, p)

      | Msort (an, c, fn, k) ->
        let pp fmt (an, c, fn, k) =
          Format.fprintf fmt "sort_%a_%a (%a)"
            pp_str an
            pp_str fn
            f c
            (* pp_sort_kind k *) (* TODO: asc / desc *)
        in
        pp fmt (an, c, fn, k)

      | Mcontains (an, c, i) ->
        let pp fmt (an, c, i) =
          Format.fprintf fmt "contains_%a (%a, %a)"
            pp_str an
            f c
            f i
        in
        pp fmt (an, c, i)

      | Mnth (an, c, i) ->
        let pp fmt (an, c, i) =
          Format.fprintf fmt "nth_%a (%a, %a)"
            pp_str an
            f c
            f i
        in
        pp fmt (an, c, i)

      | Mcount (an, c) ->
        let pp fmt (an, c) =
          Format.fprintf fmt "count_%a (%a)"
            pp_str an
            f c
        in
        pp fmt (an, c)

      | Msum (an, fd, c) ->
        let pp fmt (an, fd, c) =
          Format.fprintf fmt "sum_%a_%a (_s)"
            pp_str an
            pp_id fd
            (* f c *)
        in
        pp fmt (an, fd, c)

      | Mmin (an, fd, c) ->
        let pp fmt (an, fd, c) =
          Format.fprintf fmt "min_%a_%a (%a)"
            pp_str an
            pp_id fd
            f c
        in
        pp fmt (an, fd, c)

      | Mmax (an, fd, c) ->
        let pp fmt (an, fd, c) =
          Format.fprintf fmt "max_%a_%a (%a)"
            pp_str an
            pp_id fd
            f c
        in
        pp fmt (an, fd, c)

      | Mfail (msg) ->
        Format.fprintf fmt "Current.failwith %a"
          f msg

      | Mmathmin (l, r) ->
        Format.fprintf fmt "min (%a, %a)"
          f l
          f r

      | Mmathmax (l, r) ->
        Format.fprintf fmt "max (%a, %a)"
          f l
          f r

      | Mand (l, r) ->
        let pp fmt (l, r) =
          Format.fprintf fmt "%a and %a"
            f l
            f r
        in
        pp fmt (l, r)

      | Mor (l, r) ->
        let pp fmt (l, r) =
          Format.fprintf fmt "%a or %a"
            f l
            f r
        in
        pp fmt (l, r)

      | Mimply (l, r) ->
        let pp fmt (l, r) =
          Format.fprintf fmt "%a -> %a"
            f l
            f r
        in
        pp fmt (l, r)

      | Mequiv  (l, r) ->
        let pp fmt (l, r) =
          Format.fprintf fmt "%a <-> %a"
            f l
            f r
        in
        pp fmt (l, r)

      | Mnot e ->
        let pp fmt e =
          Format.fprintf fmt "not (%a)"
            f e
        in
        pp fmt e

      | Mequal (l, r) ->
        let pp fmt (l, r : mterm * mterm) =
          Format.fprintf fmt "%a = %a"
            (pp_cast Lhs l.type_ r.type_ f) l
            (pp_cast Rhs l.type_ r.type_ f) r
        in
        pp fmt (l, r)

      | Mnequal (l, r) ->
        let pp fmt (l, r : mterm * mterm) =
          Format.fprintf fmt "%a <> %a"
            (pp_cast Lhs l.type_ r.type_ f) l
            (pp_cast Rhs l.type_ r.type_ f) r
        in
        pp fmt (l, r)

      | Mgt (l, r) ->
        let pp fmt (l, r : mterm * mterm) =
          Format.fprintf fmt "%a > %a"
            (pp_cast Lhs l.type_ r.type_ f) l
            (pp_cast Rhs l.type_ r.type_ f) r
        in
        pp fmt (l, r)

      | Mge (l, r) ->
        let pp fmt (l, r : mterm * mterm) =
          Format.fprintf fmt "%a >= %a"
            (pp_cast Lhs l.type_ r.type_ f) l
            (pp_cast Rhs l.type_ r.type_ f) r
        in
        pp fmt (l, r)

      | Mlt (l, r) ->
        let pp fmt (l, r : mterm * mterm) =
          Format.fprintf fmt "%a < %a"
            (pp_cast Lhs l.type_ r.type_ f) l
            (pp_cast Rhs l.type_ r.type_ f) r
        in
        pp fmt (l, r)

      | Mle (l, r) ->
        let pp fmt (l, r : mterm * mterm) =
          Format.fprintf fmt "%a <= %a"
            (pp_cast Lhs l.type_ r.type_ f) l
            (pp_cast Rhs l.type_ r.type_ f) r
        in
        pp fmt (l, r)

      | Mplus (l, r) ->
        let pp fmt (l, r : mterm * mterm) =
          Format.fprintf fmt "%a + %a"
            (pp_cast Lhs l.type_ r.type_ f) l
            (pp_cast Rhs l.type_ r.type_ f) r
        in
        pp fmt (l, r)

      | Mminus (l, r) ->
        let pp fmt (l, r : mterm * mterm) =
          Format.fprintf fmt "%a - %a"
            (pp_cast Lhs l.type_ r.type_ f) l
            (pp_cast Rhs l.type_ r.type_ f) r
        in
        pp fmt (l, r)

      | Mmult (l, r) ->
        let pp fmt (l, r : mterm * mterm) =
          Format.fprintf fmt "%a * %a"
            (pp_cast Lhs l.type_ r.type_ f) l
            (pp_cast Rhs l.type_ r.type_ f) r
        in
        pp fmt (l, r)

      | Mdiv (l, r) ->
        let pp fmt (l, r : mterm * mterm) =
          Format.fprintf fmt "%a / %a"
            (pp_cast Lhs l.type_ r.type_ f) l
            (pp_cast Rhs l.type_ r.type_ f) r
        in
        pp fmt (l, r)

      | Mmodulo (l, r) ->
        let pp fmt (l, r : mterm * mterm) =
          Format.fprintf fmt "%a %% %a"
            (pp_cast Lhs l.type_ r.type_ f) l
            (pp_cast Rhs l.type_ r.type_ f) r
        in
        pp fmt (l, r)

      | Muplus e ->
        let pp fmt e =
          Format.fprintf fmt "+%a"
            f e
        in
        pp fmt e

      | Muminus e ->
        let pp fmt e =
          Format.fprintf fmt "-%a"
            f e
        in
        pp fmt e

      | Mrecord l ->
        let asset_name =
          match mtt.type_ with
          | Tasset asset_name -> asset_name
          | _ -> assert false
        in
        let a = Utils.get_record model asset_name in
        let ll = List.map (fun (x : record_item) -> x.name) a.values in

        let lll = List.map2 (fun x y -> (x, y)) ll l in

        Format.fprintf fmt "{ %a }"
          (pp_list "; " (fun fmt (a, b)->
               Format.fprintf fmt "%a = %a"
                 pp_id a
                 f b)) lll
      | Mletin (ids, ({node = Mseq l} as a), t, b) ->
        Format.fprintf fmt "let %a%a =@\n%ain@\n@[%a@]"
          (pp_if (List.length ids > 1) (pp_paren (pp_list ", " pp_id)) (pp_list ", " pp_id)) ids
          (pp_option (fun fmt -> Format.fprintf fmt  " : %a" pp_type)) t
          f a
          f b
      | Mletin (ids, a, t, b) ->
        Format.fprintf fmt "let %a%a = %a in@\n@[%a@]"
          (pp_if (List.length ids > 1) (pp_paren (pp_list ", " pp_id)) (pp_list ", " pp_id)) ids
          (pp_option (fun fmt -> Format.fprintf fmt  " : %a" pp_type)) t
          f a
          f b
      | Mvarstorevar v -> Format.fprintf fmt "_s.%a" pp_id v
      | Mvarstorecol v -> Format.fprintf fmt "_s.%a_keys" pp_id v
      | Mvarenumval v  -> pp_id fmt v
      | Mvarfield v    -> pp_id fmt v
      | Mvarlocal v    -> pp_id fmt v
      | Mvarthe        -> pp_str fmt "the"
      | Mstate         -> pp_str fmt "state"
      | Mnow           -> pp_str fmt "Current.time()"
      | Mtransferred   -> pp_str fmt "Current.amount()"
      | Mcaller        -> pp_str fmt "Current.sender()"
      | Mbalance       -> pp_str fmt "Current.balance()"
      | Mnone          -> pp_str fmt "None"
      | Msome v        ->
        Format.fprintf fmt "Some (%a)"
          f v
      | Marray l ->
        Format.fprintf fmt "[%a]"
          (pp_list "; " f) l
      | Mint v -> pp_big_int fmt v
      | Muint v -> pp_big_int fmt v
      | Mbool b -> pp_str fmt (if b then "true" else "false")
      | Menum v -> pp_str fmt v
      | Mrational (n, d) ->
        Format.fprintf fmt "(%a div %a)"
          pp_big_int n
          pp_big_int d
      | Mdate v -> pp_str fmt v
      | Mstring v ->
        Format.fprintf fmt "\"%a\""
          pp_str v
      | Mcurrency (v, c) ->
        Format.fprintf fmt "%a%a"
          pp_big_int v
          pp_currency c
      | Maddress v -> pp_str fmt v
      | Mduration v -> pp_str fmt v
      | Mdotasset (e, i)
      | Mdotcontract (e, i) ->
        Format.fprintf fmt "%a.%a"
          f e
          pp_id i
      | Mtuple l ->
        Format.fprintf fmt "(%a)"
          (pp_list ", " f) l
      | Mfor (i, c, b) ->
        Format.fprintf fmt "for (%a in %a)@\n (@[<v 2>%a@])@\n"
          pp_id i
          f c
          f b
      | Mfold (i, is, c, b) ->
        let t : lident option =
          match c with
          | {node = Mvarstorecol an; _} -> Some an
          | _ -> None
        in

        let cond = Option.is_some t in

        Format.fprintf fmt
          "List.fold (fun (%a, (%a)) ->@\n\
           %a@[  %a@]) %a (%a)@\n"
          pp_id i (pp_list ", " pp_id) is
          (pp_do_if cond (fun fmt c ->
               let an = Option.get t in
               Format.fprintf fmt "let %a : %a = get_%a (_s, %a) in  @\n"
                 pp_id i
                 pp_id an
                 pp_id an
                 pp_id i)) c
          f b
          f c
          (pp_list ", " pp_id) is
      | Mseq is ->
        Format.fprintf fmt "@[%a@]"
          (pp_list ";@\n" f) is

      | Massign (op, l, r) ->
        Format.fprintf fmt "%a %a %a"
          pp_id l
          pp_operator op
          f r
      | Massignfield (op, a, field , r) ->
        Format.fprintf fmt "%a.%a %a %a"
          pp_id a
          pp_id field
          pp_operator op
          f r
      | Mtransfer (x, b, q) ->
        Format.fprintf fmt "transfer%s %a%a"
          (if b then " back" else "")
          f x
          (pp_option (fun fmt -> Format.fprintf fmt " to %a" pp_qualid)) q
      | Mbreak -> emit_error UnsupportedBreak
      | Massert x ->
        Format.fprintf fmt "assert %a"
          f x
      | Mreturn x ->
        Format.fprintf fmt "return %a"
          f x
      | Mtokeys (an, x) ->
        Format.fprintf fmt "%s.to_keys (%a)"
          an
          f x
      | Mforall _                        -> emit_error (UnsupportedTerm ("forall"))
      | Mexists _                        -> emit_error (UnsupportedTerm ("exists"))
      | Msetbefore _                     -> emit_error (UnsupportedTerm ("setbefore"))
      | Msetunmoved _                    -> emit_error (UnsupportedTerm ("setunmoved"))
      | Msetadded _                      -> emit_error (UnsupportedTerm ("setadded"))
      | Msetremoved _                    -> emit_error (UnsupportedTerm ("setremoved"))
      | Msetiterated _                   -> emit_error (UnsupportedTerm ("setiterated"))
      | Msettoiterate _                  -> emit_error (UnsupportedTerm ("settoiterate"))
      | MsecMayBePerformedOnlyByRole _   -> emit_error (UnsupportedTerm ("secMayBePerformedOnlyByRole"))
      | MsecMayBePerformedOnlyByAction _ -> emit_error (UnsupportedTerm ("secMayBePerformedOnlyByAction"))
      | MsecMayBePerformedByRole _       -> emit_error (UnsupportedTerm ("secMayBePerformedByRole"))
      | MsecMayBePerformedByAction _     -> emit_error (UnsupportedTerm ("secMayBePerformedByAction"))
      | MsecTransferredBy _              -> emit_error (UnsupportedTerm ("secTransferredBy"))
      | MsecTransferredTo _              -> emit_error (UnsupportedTerm ("secTransferredTo"))
      | Manyaction                       -> emit_error (UnsupportedTerm ("anyaction"))
    in
    f fmt mt
  in

  let pp_enum_item fmt (enum_item : enum_item) =
    Format.fprintf fmt "| %a"
      pp_id enum_item.name
  in

  let pp_enum fmt (enum : enum) =
    Format.fprintf fmt "type %a =@\n[<v 2>  %a@]@\n"
      pp_id enum.name
      (pp_list "@\n" pp_enum_item) enum.values
  in

  let pp_record_item fmt (item : record_item) =
    let pp_typ fmt t =
      match t with
      | Tcontainer (Tasset an, _) ->
        let _, t = Utils.get_record_key model an in
        Format.fprintf fmt "%a list"
          pp_btyp t
      | _ -> pp_type fmt t
    in
    Format.fprintf fmt "%a : %a;"
      pp_id item.name
      pp_typ item.type_
      (* (pp_option (fun fmt -> Format.fprintf fmt " := %a" pp_mterm)) item.default *)
  in

  let pp_record fmt (record : record) =
    Format.fprintf fmt "type %a = {@\n@[<v 2>  %a@]@\n}@\n"
      pp_id record.name
      (pp_list "@\n" pp_record_item) record.values
  in

  let pp_decl fmt = function
    | Denum e -> pp_enum fmt e
    | Drecord r -> pp_record fmt r
    | _ -> ()
  in

  let pp_storage_item fmt (si : storage_item) =
    match si with
    | { asset = Some an; _} ->
      let _, t = Utils.get_record_key model an in
      Format.fprintf fmt "%s_keys: %a list;@\n%s_assets: (%a, %s) map;"
        (unloc an)
        pp_btyp t
        (unloc an)
        pp_btyp t
        (unloc an)

    | _ ->
      Format.fprintf fmt "%a : %a;"
        pp_id si.name
        pp_type si.typ
  in

  let pp_storage fmt (s : storage) =
    Format.fprintf fmt "type storage = {@\n@[<v 2>  %a@]@\n}@\n"
      (pp_list "@\n" pp_storage_item) s
  in

  let pp_init_function fmt (s : storage) =
    let pp_storage_item fmt (si : storage_item) =
      match si with
      | { asset = Some an; _} ->
        let _, t = Utils.get_record_key model an in
        Format.fprintf fmt "%s_keys = [];@\n%s_assets = (Map : (%a, %s) map);"
          (unloc an)
          (unloc an)
          pp_btyp t
          (unloc an)

      | _ ->
        Format.fprintf fmt "%a = %a;"
          pp_id si.name
          (pp_cast Rhs si.typ si.default.type_ pp_mterm) si.default
    in

    Format.fprintf fmt "let%%init initialize = {@\n@[<v 2>  %a@]@\n}@\n"
      (pp_list "@\n" pp_storage_item) s
  in

  let pp_args fmt args =
    match args with
    | [] -> Format.fprintf fmt "()"
    | [(id, t, _)] ->
      Format.fprintf fmt "(%a : %a)"
        pp_id id
        pp_type t
    | _   ->
      Format.fprintf fmt "(%a : %a)"
        (pp_list ", " (fun fmt (id, _, _) -> pp_id fmt id)) args
        (pp_list " * " (fun fmt (_ , t, _) -> pp_type fmt t)) args

  in

  let pp_function fmt f =
    let k, fs, ret, extra_arg = match f.node with
      | Entry f -> "let%entry", f, Some (Ttuple [Tcontainer (Toperation, Collection); Tstorage]), " (_s : storage)"
      | Function (f, a) -> "let", f, Some a, ""
    in
    Format.fprintf fmt "%a %a %a%s%a =@\n@[<v 2>  %a@]@\n"
      pp_str k
      pp_id fs.name
      pp_args fs.args
      extra_arg
      (pp_option (fun fmt -> Format.fprintf fmt " : %a" pp_type)) ret
      pp_mterm fs.body
  in
  Format.fprintf fmt "(* Liquidity output generated by archetype *)@\n\
                      @\n%a@\n\
                      @\n%a\
                      @\n%a\
                      @\n%a\
                      @\n%a\
                      @\n%a\
                      @\n%a\
                      @."
    pp_model_name ()
    (pp_list "@\n" pp_decl) model.decls
    pp_storage model.storage
    pp_init_function model.storage
    pp_utils model.api_items
    pp_api_items model.api_items
    (pp_list "@\n" pp_function) model.functions

(* -------------------------------------------------------------------------- *)
let string_of__of_pp pp x =
  Format.asprintf "%a@." pp x

let show_model (x : model) = string_of__of_pp pp_model x
