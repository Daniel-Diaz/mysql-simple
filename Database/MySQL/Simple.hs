module Database.MySQL.Simple
    (
      execute
    , query
    , formatQuery
    ) where

import Control.Applicative
import Data.Int (Int64)
import Control.Monad.Fix
import Blaze.ByteString.Builder
import qualified Data.ByteString.Char8 as B
import Data.ByteString (ByteString)
import Data.Monoid
import Database.MySQL.Base (Connection)
import qualified Database.MySQL.Base as Base
import Database.MySQL.Simple.Param
import Database.MySQL.Simple.QueryParams
import Database.MySQL.Simple.QueryResults
import Database.MySQL.Simple.Types

formatQuery :: QueryParams q => Connection -> Query -> q -> IO ByteString
formatQuery conn (Query template) qs
    | '?' `B.notElem` template = return template
    | otherwise =
        toByteString . zipParams (split template) <$> mapM sub (renderParams qs)
  where sub (Plain b)  = pure b
        sub (Escape s) = (inQuotes . fromByteString) <$> Base.escape conn s
        split q = fromByteString h : if B.null t then [] else split (B.tail t)
            where (h,t) = B.break (=='?') q
        zipParams (t:ts) (p:ps) = t `mappend` p `mappend` zipParams ts ps
        zipParams [] []         = mempty
        zipParams [] _ = fmtError "more parameters than '?' characters"
        zipParams _ [] = fmtError "more '?' characters than parameters"

execute :: (QueryParams q) => Connection -> Query -> q -> IO Int64
execute conn template qs = do
  Base.query conn =<< formatQuery conn template qs
  ncols <- Base.fieldCount (Left conn)
  if ncols /= 0
    then error "execute: executed a select!"
    else Base.affectedRows conn
  
query :: (QueryParams q, QueryResults r) => Connection -> Query -> q -> IO [r]
query conn template qs = do
  Base.query conn =<< formatQuery conn template qs
  r <- Base.storeResult conn
  ncols <- Base.fieldCount (Right r)
  if ncols == 0
    then return []
    else do
      fs <- Base.fetchFields r
      flip fix [] $ \loop acc -> do
        row <- Base.fetchRow r
        case row of
          [] -> return (reverse acc)
          _  -> loop (convertResults fs row:acc)

fmtError :: String -> a
fmtError msg = error $ "Database.MySQL.formatQuery: " ++ msg