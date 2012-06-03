{-# LANGUAGE ViewPatterns,OverloadedStrings #-}
module SAT.ToySAT (CNF, solve, cnfParser) where

import Control.Applicative ((<*>), (<*))
import Control.Monad (unless)
import Data.List (sort,sortBy, delete, partition,(\\), nub, intersect,intersperse)
import Data.Maybe (mapMaybe)
import Data.Function (on)
import qualified Data.Attoparsec.Char8 as AP

data L = P { unL :: Int } | N { unL :: Int } deriving (Eq)
instance Ord L where
  compare x y = 
    case ((compare `on` unL) x y,x,y) of
      (EQ,P _,N _) -> GT
      (EQ,N _,P _) -> LT
      (EQ,_,_) -> EQ
      (c,_,_) -> c
instance Show L where
  show (P x) = show x
  show (N x) = show (-x)

neg :: L -> L
neg (P x) = N x
neg (N x) = P x

type Clause = [L]
data CNF = CNF Int [Clause]
instance Show CNF where
  show (CNF x ys) = 
    "p cnf " ++ (show x) ++ " " ++ (show $ length ys) ++ "\n"
    ++ (concatMap ((++ " 0\n").concat.intersperse " ".map show) ys)





{-| CNFを充足する解のリストを得ます 
  
要テスト: 解が見つかった端から取り出せるようにする事。最後まで見つからないと出てこないのはNG。
-}
solve :: CNF -> [[L]]
solve = go [] [] . cleanupRule . (\(CNF _ x) -> x)
  where 
    go ans ls = maybe ans 
                (\(ls', cnf) ->
                  let newls = ls ++ ls'
                  in case cnf of
                    ([]) -> ans ++ [newls]
                    ((l:_):_) -> concat $ map (\x -> maybe [] (go ans (newls ++ [x])) $ resolve x cnf) [l,neg l]
                    _ -> error "Internal error"
                  ) . unitRule


{- | 探索前にCNFをクリーンアップします

   クリーンアップとは、
     1. 同一の節にLが複数現れたら、1つにまとまる。(A ∧ A)はAと等しい
     2. 同一の節にLと¬Lの両方が現れたら、その節は除去する。(A ∧ ¬A) は常に1
     3. できるだけ早く刈り込みが進むように、節の大きさが小さい順に並べる
       a. 探索木の底の方で細かいバックトラックが何度も発生するのを回避できるかも
       b. 空になった節を早く発見する事ができるかも
       c. でも、どうせ処理中にひっくり返ってしまうので、意味ないと思う...

prop> \xs -> 1 == maximum (map (maximum.(map length).group.sort) $ cleanup xs)

-}
{-# INLINE cleanupRule #-}
cleanupRule :: [Clause] -> [Clause]
cleanupRule = map snd . sortBy (compare `on` fst) . mapMaybe (f (0 :: Int) [] . sort)
  where
    f n zs [] = Just (n, zs)
    f n zs [x] = Just (succ n, (x:zs))
    f n zs (x:xs@(y:_))
      | x == y     = f n zs xs
      | x == neg y = Nothing
      | otherwise  = f (succ n) (x:zs) xs



{- | 単一リテラル規則
   一つのリテラルLのみからなる節が存在した場合、Lは常に真で無くてはいけない
  という事なので、Lを含む節を節ごと除去し、¬Lを含む節はその節から¬Lを除去します。
  
  以下の場合は、節集合は充足不能なのでNothingを返します。
    1. Lのみからなる節と¬Lのみからなる節の両方を発見した場合
    2. 空の節ができたばあい
-}
{-# INLINE unitRule #-}
unitRule :: [Clause] -> Maybe ([L], [Clause])
unitRule xs
  | not $ null $ intersect ls ls' = Nothing
  | elem [] xs'' = Nothing
  | otherwise    = Just (ls, xs'')
  where
    (nub.concat -> ls, xs') = partition (null.tail) xs
    ls' = map neg ls
    xs'' = map (\\ ls') $ filter (null.intersect ls) xs'


{- | リテラルが真であるとみなして、節集合を簡略化します
   1. Lを含む節を除去します
   2. ¬Lを除去します
   3.空の節ができた場合はNothingを戻します
-}
resolve :: L -> [Clause] -> Maybe [Clause]
resolve l xs 
  | elem [] newclauses = Nothing
  | otherwise = Just newclauses
  where 
    newclauses = map (delete (neg l)) $ filter (not.elem l) xs



{- =============================== -}

cnfParser :: AP.Parser CNF
cnfParser = 
  do { 
    AP.skipMany commentParser;
    AP.string "p cnf "; spc; n <- AP.decimal :: AP.Parser Int; spc; m <- AP.decimal; AP.endOfLine;
    cnf <- if m > 1 then AP.many1 (clauseParser n >>= return . filter ((/= 0).unL)) else return [];
    unless (length cnf == m) $ fail $ "Mismatch number of clauses. specified " ++ (show m) ++ ", But take " ++ (show $ length cnf);
    AP.endOfInput; 
    return $ CNF n cnf
    } AP.<?> "CNF"
  where
    spc = AP.skipWhile (flip elem " \t") -- skipSpaceは改行もスキップするので使えない?
    commentParser = do { AP.char 'c'; AP.skipWhile (/= '\n'); AP.endOfLine }
    clauseParser n = do { AP.many1 (litParser n) <* spc  <* AP.endOfLine } AP.<?> "Clause"
    litParser n = do { spc; AP.option P (AP.char '-' >> return N) <*> AP.decimal} AP.<?> "Literal"

