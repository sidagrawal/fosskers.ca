{-# LANGUAGE DataKinds, TypeOperators #-}
{-# LANGUAGE DeriveGeneric, DeriveAnyClass, StandaloneDeriving #-}

module Fosskers.Common where

import Data.Aeson (ToJSON)
import Lucid
import Protolude
import Servant.API
import Servant.HTML.Lucid
import Time.Types

---

type JsonAPI = "posts" :> Get '[JSON] [Blog]

type API = JsonAPI
  :<|> "blog" :> Raw
  :<|> "assets" :> Raw
  :<|> "webfonts" :> Raw
  :<|> Get '[HTML] (Html ())

newtype Title = Title Text deriving (Eq, Show, Generic, ToJSON)

-- Evil evil orphan instances.
deriving instance Generic Date
deriving instance ToJSON Date
deriving instance Generic Month
deriving instance ToJSON Month

newtype Path = Path Text deriving (Generic, ToJSON)

data Blog = Blog { title    :: Title
                 , date     :: Date
                 , filename :: Path
                 , freqs    :: [(Text, Int)] } deriving (Generic, ToJSON)