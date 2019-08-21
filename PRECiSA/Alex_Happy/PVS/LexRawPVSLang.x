-- -*- haskell -*-
-- This Alex file was machine-generated by the BNF converter
{
{-# OPTIONS -fno-warn-incomplete-patterns #-}
{-# OPTIONS_GHC -w #-}
module LexRawPVSLang where



import qualified Data.Bits
import Data.Word (Word8)
import Data.Char (ord)
}


$l = [a-zA-Z\192 - \255] # [\215 \247]    -- isolatin1 letter FIXME
$c = [A-Z\192-\221] # [\215]    -- capital isolatin1 letter FIXME
$s = [a-z\222-\255] # [\247]    -- small isolatin1 letter FIXME
$d = [0-9]                -- digit
$i = [$l $d _ ']          -- identifier character
$u = [\0-\255]          -- universal: any character

@rsyms =    -- symbols and non-identifier-like reserved words
   \( | \) | \+ | \- | \* | \/ | \^ | \, | \= | \/ \= | \< | \< \= | \> | \> \= | \: | \|

:-
"%" [.]* ; -- Toss single line comments

$white+ ;
@rsyms { tok (\p s -> PT p (eitherResIdent (TV . share) s)) }
$c ($l | $d | \_ | \?)* { tok (\p s -> PT p (eitherResIdent (T_VarId . share) s)) }
$s ($l | $d | \_ | \? | \@)* { tok (\p s -> PT p (eitherResIdent (T_NonVarId . share) s)) }

$l $i*   { tok (\p s -> PT p (eitherResIdent (TV . share) s)) }


$d+      { tok (\p s -> PT p (TI $ share s))    }
$d+ \. $d+ (e (\-)? $d+)? { tok (\p s -> PT p (TD $ share s)) }

{

tok :: (Posn -> String -> Token) -> (Posn -> String -> Token)
tok f p s = f p s

share :: String -> String
share = id

data Tok =
   TS !String !Int    -- reserved words and symbols
 | TL !String         -- string literals
 | TI !String         -- integer literals
 | TV !String         -- identifiers
 | TD !String         -- double precision float literals
 | TC !String         -- character literals
 | T_VarId !String
 | T_NonVarId !String

 deriving (Eq,Show,Ord)

data Token =
   PT  Posn Tok
 | Err Posn
  deriving (Eq,Show,Ord)

tokenPos :: [Token] -> String
tokenPos (PT (Pn _ l _) _ :_) = "line " ++ show l
tokenPos (Err (Pn _ l _) :_) = "line " ++ show l
tokenPos _ = "end of file"

tokenPosn :: Token -> Posn
tokenPosn (PT p _) = p
tokenPosn (Err p) = p

tokenLineCol :: Token -> (Int, Int)
tokenLineCol = posLineCol . tokenPosn

posLineCol :: Posn -> (Int, Int)
posLineCol (Pn _ l c) = (l,c)

mkPosToken :: Token -> ((Int, Int), String)
mkPosToken t@(PT p _) = (posLineCol p, prToken t)

prToken :: Token -> String
prToken t = case t of
  PT _ (TS s _) -> s
  PT _ (TL s)   -> show s
  PT _ (TI s)   -> s
  PT _ (TV s)   -> s
  PT _ (TD s)   -> s
  PT _ (TC s)   -> s
  PT _ (T_VarId s) -> s
  PT _ (T_NonVarId s) -> s


data BTree = N | B String Tok BTree BTree deriving (Show)

eitherResIdent :: (String -> Tok) -> String -> Tok
eitherResIdent tv s = treeFind resWords
  where
  treeFind N = tv s
  treeFind (B a t left right) | s < a  = treeFind left
                              | s > a  = treeFind right
                              | s == a = t

resWords :: BTree
resWords = b "NOT" 53 (b "Dmod" 27 (b ">=" 14 (b "/" 7 (b "+" 4 (b ")" 2 (b "(" 1 N N) (b "*" 3 N N)) (b "-" 6 (b "," 5 N N) N)) (b "<=" 11 (b ":" 9 (b "/=" 8 N N) (b "<" 10 N N)) (b ">" 13 (b "=" 12 N N) N))) (b "Datan" 21 (b "Dacos" 18 (b "BEGIN" 16 (b "AND" 15 N N) (b "Dabs" 17 N N)) (b "Dasin" 20 (b "Dadd" 19 N N) N)) (b "Dexp" 24 (b "Ddiv" 23 (b "Dcos" 22 N N) N) (b "Dln" 26 (b "Dfloor" 25 N N) N)))) (b "IF" 40 (b "DtoR" 34 (b "Dsqrt" 31 (b "Dneg" 29 (b "Dmul" 28 N N) (b "Dsin" 30 N N)) (b "Dtan" 33 (b "Dsub" 32 N N) N)) (b "END" 37 (b "ELSIF" 36 (b "ELSE" 35 N N) N) (b "FALSE" 39 (b "ENDIF" 38 N N) N))) (b "Imul" 47 (b "Iadd" 44 (b "IN" 42 (b "IMPORTING" 41 N N) (b "Iabs" 43 N N)) (b "Imod" 46 (b "Idiv" 45 N N) N)) (b "ItoD" 50 (b "Isub" 49 (b "Ineg" 48 N N) N) (b "LET" 52 (b "ItoS" 51 N N) N))))) (b "^" 80 (b "Sln" 67 (b "Sadd" 60 (b "RtoS" 57 (b "PI" 55 (b "OR" 54 N N) (b "RtoD" 56 N N)) (b "Sacos" 59 (b "Sabs" 58 N N) N)) (b "Sdiv" 64 (b "Satan" 62 (b "Sasin" 61 N N) (b "Scos" 63 N N)) (b "Sfloor" 66 (b "Sexp" 65 N N) N))) (b "Stan" 74 (b "Ssin" 71 (b "Smul" 69 (b "Smod" 68 N N) (b "Sneg" 70 N N)) (b "Ssub" 73 (b "Ssqrt" 72 N N) N)) (b "THEORY" 77 (b "THEN" 76 (b "StoR" 75 N N) N) (b "VAR" 79 (b "TRUE" 78 N N) N)))) (b "pi" 93 (b "floor" 87 (b "atan" 84 (b "acos" 82 (b "abs" 81 N N) (b "asin" 83 N N)) (b "exp" 86 (b "cos" 85 N N) N)) (b "integer" 90 (b "int" 89 (b "for" 88 N N) N) (b "mod" 92 (b "ln" 91 N N) N))) (b "unb_nz_single" 100 (b "tan" 97 (b "sqrt" 95 (b "sin" 94 N N) (b "subrange" 96 N N)) (b "unb_nz_double" 99 (b "unb_double" 98 N N) N)) (b "unb_single" 103 (b "unb_pos_single" 102 (b "unb_pos_double" 101 N N) N) (b "|" 105 (b "warning" 104 N N) N)))))
   where b s n = let bs = id s
                  in B bs (TS bs n)

unescapeInitTail :: String -> String
unescapeInitTail = id . unesc . tail . id where
  unesc s = case s of
    '\\':c:cs | elem c ['\"', '\\', '\''] -> c : unesc cs
    '\\':'n':cs  -> '\n' : unesc cs
    '\\':'t':cs  -> '\t' : unesc cs
    '"':[]    -> []
    c:cs      -> c : unesc cs
    _         -> []

-------------------------------------------------------------------
-- Alex wrapper code.
-- A modified "posn" wrapper.
-------------------------------------------------------------------

data Posn = Pn !Int !Int !Int
      deriving (Eq, Show,Ord)

alexStartPos :: Posn
alexStartPos = Pn 0 1 1

alexMove :: Posn -> Char -> Posn
alexMove (Pn a l c) '\t' = Pn (a+1)  l     (((c+7) `div` 8)*8+1)
alexMove (Pn a l c) '\n' = Pn (a+1) (l+1)   1
alexMove (Pn a l c) _    = Pn (a+1)  l     (c+1)

type Byte = Word8

type AlexInput = (Posn,     -- current position,
                  Char,     -- previous char
                  [Byte],   -- pending bytes on the current char
                  String)   -- current input string

tokens :: String -> [Token]
tokens str = go (alexStartPos, '\n', [], str)
    where
      go :: AlexInput -> [Token]
      go inp@(pos, _, _, str) =
               case alexScan inp 0 of
                AlexEOF                   -> []
                AlexError (pos, _, _, _)  -> [Err pos]
                AlexSkip  inp' len        -> go inp'
                AlexToken inp' len act    -> act pos (take len str) : (go inp')

alexGetByte :: AlexInput -> Maybe (Byte,AlexInput)
alexGetByte (p, c, (b:bs), s) = Just (b, (p, c, bs, s))
alexGetByte (p, _, [], s) =
  case  s of
    []  -> Nothing
    (c:s) ->
             let p'     = alexMove p c
                 (b:bs) = utf8Encode c
              in p' `seq` Just (b, (p', c, bs, s))

alexInputPrevChar :: AlexInput -> Char
alexInputPrevChar (p, c, bs, s) = c

-- | Encode a Haskell String to a list of Word8 values, in UTF8 format.
utf8Encode :: Char -> [Word8]
utf8Encode = map fromIntegral . go . ord
 where
  go oc
   | oc <= 0x7f       = [oc]

   | oc <= 0x7ff      = [ 0xc0 + (oc `Data.Bits.shiftR` 6)
                        , 0x80 + oc Data.Bits..&. 0x3f
                        ]

   | oc <= 0xffff     = [ 0xe0 + (oc `Data.Bits.shiftR` 12)
                        , 0x80 + ((oc `Data.Bits.shiftR` 6) Data.Bits..&. 0x3f)
                        , 0x80 + oc Data.Bits..&. 0x3f
                        ]
   | otherwise        = [ 0xf0 + (oc `Data.Bits.shiftR` 18)
                        , 0x80 + ((oc `Data.Bits.shiftR` 12) Data.Bits..&. 0x3f)
                        , 0x80 + ((oc `Data.Bits.shiftR` 6) Data.Bits..&. 0x3f)
                        , 0x80 + oc Data.Bits..&. 0x3f
                        ]
}