-- -*- haskell -*- File generated by the BNF Converter (bnfc 2.9.4.1).

-- Lexer definition for use with Alex 3
{
{-# OPTIONS -fno-warn-incomplete-patterns #-}
{-# OPTIONS_GHC -w #-}

{-# LANGUAGE PatternSynonyms #-}

module Parser.LexFPCoreLang where

import Prelude

import qualified Data.Bits
import Data.Char     (ord)
import Data.Function (on)
import Data.Word     (Word8)
}

-- Predefined character classes

$c = [A-Z\192-\221] # [\215]  -- capital isolatin1 letter (215 = \times) FIXME
$s = [a-z\222-\255] # [\247]  -- small   isolatin1 letter (247 = \div  ) FIXME
$l = [$c $s]         -- letter
$d = [0-9]           -- digit
$i = [$l $d _ ']     -- identifier character
$u = [. \n]          -- universal: any character

-- Symbols and non-identifier-like reserved words

@rsyms = \( | \) | \: | \! | "let" \* | "while" \* | "for" \* | "tensor" \* | \[ | \] | \+ | \- | \* | \/ | \< | \> | \< \= | \> \= | \= \= | \! \=

:-

-- Line comment ";"
";" [.]* ;

-- Whitespace (skipped)
$white+ ;

-- Symbols
@rsyms
    { tok (eitherResIdent TV) }

-- token Rational
[\+ \-]? $d + \/ $d * [1 2 3 4 5 6 7 8 9]$d *
    { tok (eitherResIdent T_Rational) }

-- token DecNum
[\+ \-]? ($d + (\. $d +)? | \. $d +)(e [\+ \-]? $d +)?
    { tok (eitherResIdent T_DecNum) }

-- token HexNum
[\+ \-]? 0 x (([a b c d e f]| $d)+ (\. ([a b c d e f]| $d)+)? | \. ([a b c d e f]| $d)+)(p [\+ \-]? $d +)?
    { tok (eitherResIdent T_HexNum) }

-- token Symbol
([\! \$ \% \& \* \+ \- \. \/ \< \= \> \? \@ \\ \^ \_ \~]| $l)([\! \$ \% \& \* \+ \- \. \/ \: \< \= \> \? \@ \\ \^ \_ \~]| ($d | $l)) *
    { tok (eitherResIdent T_Symbol) }

-- Keywords and Ident
$l $i*
    { tok (eitherResIdent TV) }

-- String
\" ([$u # [\" \\ \n]] | (\\ (\" | \\ | \' | n | t | r | f)))* \"
    { tok (TL . unescapeInitTail) }

{
-- | Create a token with position.
tok :: (String -> Tok) -> (Posn -> String -> Token)
tok f p = PT p . f

-- | Token without position.
data Tok
  = TK {-# UNPACK #-} !TokSymbol  -- ^ Reserved word or symbol.
  | TL !String                    -- ^ String literal.
  | TI !String                    -- ^ Integer literal.
  | TV !String                    -- ^ Identifier.
  | TD !String                    -- ^ Float literal.
  | TC !String                    -- ^ Character literal.
  | T_Rational !String
  | T_DecNum !String
  | T_HexNum !String
  | T_Symbol !String
  deriving (Eq, Show, Ord)

-- | Smart constructor for 'Tok' for the sake of backwards compatibility.
pattern TS :: String -> Int -> Tok
pattern TS t i = TK (TokSymbol t i)

-- | Keyword or symbol tokens have a unique ID.
data TokSymbol = TokSymbol
  { tsText :: String
      -- ^ Keyword or symbol text.
  , tsID   :: !Int
      -- ^ Unique ID.
  } deriving (Show)

-- | Keyword/symbol equality is determined by the unique ID.
instance Eq  TokSymbol where (==)    = (==)    `on` tsID

-- | Keyword/symbol ordering is determined by the unique ID.
instance Ord TokSymbol where compare = compare `on` tsID

-- | Token with position.
data Token
  = PT  Posn Tok
  | Err Posn
  deriving (Eq, Show, Ord)

-- | Pretty print a position.
printPosn :: Posn -> String
printPosn (Pn _ l c) = "line " ++ show l ++ ", column " ++ show c

-- | Pretty print the position of the first token in the list.
tokenPos :: [Token] -> String
tokenPos (t:_) = printPosn (tokenPosn t)
tokenPos []    = "end of file"

-- | Get the position of a token.
tokenPosn :: Token -> Posn
tokenPosn (PT p _) = p
tokenPosn (Err p)  = p

-- | Get line and column of a token.
tokenLineCol :: Token -> (Int, Int)
tokenLineCol = posLineCol . tokenPosn

-- | Get line and column of a position.
posLineCol :: Posn -> (Int, Int)
posLineCol (Pn _ l c) = (l,c)

-- | Convert a token into "position token" form.
mkPosToken :: Token -> ((Int, Int), String)
mkPosToken t = (tokenLineCol t, tokenText t)

-- | Convert a token to its text.
tokenText :: Token -> String
tokenText t = case t of
  PT _ (TS s _) -> s
  PT _ (TL s)   -> show s
  PT _ (TI s)   -> s
  PT _ (TV s)   -> s
  PT _ (TD s)   -> s
  PT _ (TC s)   -> s
  Err _         -> "#error"
  PT _ (T_Rational s) -> s
  PT _ (T_DecNum s) -> s
  PT _ (T_HexNum s) -> s
  PT _ (T_Symbol s) -> s

-- | Convert a token to a string.
prToken :: Token -> String
prToken t = tokenText t

-- | Finite map from text to token organized as binary search tree.
data BTree
  = N -- ^ Nil (leaf).
  | B String Tok BTree BTree
      -- ^ Binary node.
  deriving (Show)

-- | Convert potential keyword into token or use fallback conversion.
eitherResIdent :: (String -> Tok) -> String -> Tok
eitherResIdent tv s = treeFind resWords
  where
  treeFind N = tv s
  treeFind (B a t left right) =
    case compare s a of
      LT -> treeFind left
      GT -> treeFind right
      EQ -> t

-- | The keywords and symbols of the language organized as binary search tree.
resWords :: BTree
resWords =
  b "digits" 50
    (b "M_2_SQRTPI" 25
       (b ">" 13
          (b "-" 7
             (b ")" 4
                (b "!=" 2 (b "!" 1 N N) (b "(" 3 N N)) (b "+" 6 (b "*" 5 N N) N))
             (b "<" 10 (b ":" 9 (b "/" 8 N N) N) (b "==" 12 (b "<=" 11 N N) N)))
          (b "LN10" 19
             (b "FALSE" 16
                (b "E" 15 (b ">=" 14 N N) N)
                (b "INFINITY" 18 (b "FPCore" 17 N N) N))
             (b "LOG2E" 22
                (b "LOG10E" 21 (b "LN2" 20 N N) N)
                (b "M_2_PI" 24 (b "M_1_PI" 23 N N) N))))
       (b "array" 38
          (b "TRUE" 32
             (b "PI_4" 29
                (b "PI" 27 (b "NAN" 26 N N) (b "PI_2" 28 N N))
                (b "SQRT2" 31 (b "SQRT1_2" 30 N N) N))
             (b "acos" 35
                (b "]" 34 (b "[" 33 N N) N) (b "and" 37 (b "acosh" 36 N N) N)))
          (b "cast" 44
             (b "atan" 41
                (b "asinh" 40 (b "asin" 39 N N) N)
                (b "atanh" 43 (b "atan2" 42 N N) N))
             (b "copysign" 47
                (b "ceil" 46 (b "cbrt" 45 N N) N)
                (b "cosh" 49 (b "cos" 48 N N) N)))))
    (b "log" 75
       (b "fmod" 63
          (b "fabs" 57
             (b "exp" 54
                (b "erf" 52 (b "dim" 51 N N) (b "erfc" 53 N N))
                (b "expm1" 56 (b "exp2" 55 N N) N))
             (b "fma" 60
                (b "floor" 59 (b "fdim" 58 N N) N)
                (b "fmin" 62 (b "fmax" 61 N N) N)))
          (b "isinf" 69
             (b "hypot" 66
                (b "for*" 65 (b "for" 64 N N) N)
                (b "isfinite" 68 (b "if" 67 N N) N))
             (b "let" 72
                (b "isnormal" 71 (b "isnan" 70 N N) N)
                (b "lgamma" 74 (b "let*" 73 N N) N))))
       (b "sin" 87
          (b "or" 81
             (b "log2" 78
                (b "log1p" 77 (b "log10" 76 N N) N)
                (b "not" 80 (b "nearbyint" 79 N N) N))
             (b "remainder" 84
                (b "ref" 83 (b "pow" 82 N N) N)
                (b "signbit" 86 (b "round" 85 N N) N)))
          (b "tensor" 93
             (b "sqrt" 90
                (b "size" 89 (b "sinh" 88 N N) N) (b "tanh" 92 (b "tan" 91 N N) N))
             (b "trunc" 96
                (b "tgamma" 95 (b "tensor*" 94 N N) N)
                (b "while*" 98 (b "while" 97 N N) N)))))
  where
  b s n = B bs (TS bs n)
    where
    bs = s

-- | Unquote string literal.
unescapeInitTail :: String -> String
unescapeInitTail = id . unesc . tail . id
  where
  unesc s = case s of
    '\\':c:cs | elem c ['\"', '\\', '\''] -> c : unesc cs
    '\\':'n':cs  -> '\n' : unesc cs
    '\\':'t':cs  -> '\t' : unesc cs
    '\\':'r':cs  -> '\r' : unesc cs
    '\\':'f':cs  -> '\f' : unesc cs
    '"':[]       -> []
    c:cs         -> c : unesc cs
    _            -> []

-------------------------------------------------------------------
-- Alex wrapper code.
-- A modified "posn" wrapper.
-------------------------------------------------------------------

data Posn = Pn !Int !Int !Int
  deriving (Eq, Show, Ord)

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
  case s of
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