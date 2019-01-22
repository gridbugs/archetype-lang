(* Lexer *)
{
  open Core
  open Parser

  let lex_error lexbuf msg =
    let loc = Location.of_lexbuf lexbuf in
    raise (Parseutils.ParseError (Some loc, PE_LexicalError msg))

  let keywords = Hashtbl.create 0

  let keywords_ =
    [ "use"                 , USE            ;
      "model"               , MODEL          ;
      "constant"            , CONSTANT       ;
      "value"               , VALUE          ;
      "role"                , ROLE           ;
      "identified"          , IDENTIFIED     ;
      "sorted"              , SORTED         ;
      "by"                  , BY             ;
      "as"                  , AS             ;
      "from"                , FROM           ;
      "to"                  , TO             ;
      "ref"                 , REF            ;
      "fun"                 , FUN            ;
      "initialized"         , INITIALIZED    ;
      "collection"          , COLLECTION     ;
      "queue"               , QUEUE          ;
      "stack"               , STACK          ;
      "set"                 , SET            ;
      "partition"           , PARTITION      ;
      "asset"               , ASSET          ;
      "with"                , WITH           ;
      "assert"              , ASSERT         ;
      "object"              , OBJECT         ;
      "key"                 , KEY            ;
      "of"                  , OF             ;
      "enum"                , ENUM           ;
      "states"              , STATES         ;
      "initial"             , INITIAL        ;
      "ensure"              , ENSURE         ;
      "invariant"           , INVARIANT      ;
      "transition"          , TRANSITION     ;
      "transaction"         , TRANSACTION    ;
      "args"                , ARGS           ;
      "called"              , CALLED         ;
      "condition"           , CONDITION      ;
      "transferred"         , TRANSFERRED    ;
      "action"              , ACTION         ;
      "let"                 , LET            ;
      "if"                  , IF             ;
      "then"                , THEN           ;
      "else"                , ELSE           ;
      "for"                 , FOR            ;
      "in"                  , IN             ;
      "break"               , BREAK          ;
      "transfer"            , TRANSFER       ;
      "back"                , BACK           ;
      "extension"           , EXTENSION      ;
      "namespace"           , NAMESPACE      ;
      "and"                 , AND            ;
      "or"                  , OR             ;
      "not"                 , NOT            ;
      "forall"              , FORALL         ;
      "exists"              , EXISTS         ;
      "true"                , TRUE           ;
      "false"               , FALSE          ;
    ]

  let () =
    List.iter (fun (k, v) -> Hashtbl.add keywords k v) keywords_
}

(* -------------------------------------------------------------------- *)
let blank   = [' ' '\t' '\r']
let newline = '\n'
let digit   = ['0'-'9']
let float   = ['0'-'9']+ '.' ['0'-'9']+
let var     = "<%" ['a'-'z' 'A'-'Z'] ['a'-'z' 'A'-'Z' '0'-'9' '_' ]* '>'
let ident   = (['a'-'z' 'A'-'Z'] | var)  (['a'-'z' 'A'-'Z' '0'-'9' '_' ] | var)*

(* -------------------------------------------------------------------- *)
rule token = parse
  | newline               { Lexing.new_line lexbuf; token lexbuf }
  | blank+                { token lexbuf }

  | ident as id            { try  Hashtbl.find keywords id with Not_found -> IDENT id }
  | float as f            { FLOAT (float_of_string f) }
  | digit+ as n           { NUMBER (Big_int.big_int_of_string n) }


  | "(*"                  { comment lexbuf; token lexbuf }
  | "\""                  { STRING (Buffer.contents (string (Buffer.create 0) lexbuf)) }
  | "=>"                  { EQUALGREATER }
  | "::"                  { COLONCOLON }
  | "("                   { LPAREN }
  | ")"                   { RPAREN }
  | "[%"                  { LBRACKETPERCENT }
  | "["                   { LBRACKET }
  | "]"                   { RBRACKET }
  | "{"                   { LBRACE }
  | "}"                   { RBRACE }
  | "="                   { EQUAL }
  | ","                   { COMMA }
  | ":"                   { COLON }
  | ";"                   { SEMI_COLON }
  | "%"                   { PERCENT }
  | "|"                   { PIPE }
  | "."                   { DOT }
  | ":="                  { COLONEQUAL }
  | "+="                  { PLUSEQUAL }
  | "-="                  { MINUSEQUAL }
  | "*="                  { MULTEQUAL }
  | "/="                  { DIVEQUAL }
  | "&="                  { ANDEQUAL }
  | "|="                  { OREQUAL }
  | "->"                  { IMPLY }
  | "<->"                 { EQUIV }
  | "<>"                  { NEQUAL }
  | "<"                   { LESS }
  | "<="                  { LESSEQUAL }
  | ">"                   { GREATER }
  | ">="                  { GREATEREQUAL }
  | "+"                   { PLUS }
  | "-"                   { MINUS }
  | "*"                   { MULT }
  | "/"                   { DIV }
  | eof                   { EOF }
  | _ as c                {
      lex_error lexbuf (Printf.sprintf "unexpected char: %c" c)
    }

(* -------------------------------------------------------------------- *)
and comment = parse
  | "*)" { () }
  | "(*" { comment lexbuf; comment lexbuf }
  | _    { comment lexbuf }
  | eof  { lex_error lexbuf "unterminated comment" }

and string buf = parse
  | "\""          { buf }
  | "\\n"         { Buffer.add_char buf '\n'; string buf lexbuf }
  | "\\r"         { Buffer.add_char buf '\r'; string buf lexbuf }
  | "\\" (_ as c) { Buffer.add_char buf c   ; string buf lexbuf }
  | newline       { Buffer.add_string buf (Lexing.lexeme lexbuf); string buf lexbuf }
  | _ as c        { Buffer.add_char buf c   ; string buf lexbuf }
  | eof           { lex_error lexbuf "unterminated string"  }
