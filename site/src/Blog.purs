module Blog ( component, Query(..) ) where

import Prelude

import Bootstrap (col_, fluid, row, row_)
import CSS (paddingTop, pct)
import Control.Error.Util (bool)
import Control.Monad.Aff (Aff)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (class MonadEff, liftEff)
import DOM (DOM)
import DOM.Classy.Node (class IsNode, appendChild, childNodes, lastChild, removeChild)
import DOM.DOMParser (newDOMParser, parseHTMLFromString)
import DOM.Node.NodeList (item, length)
import DOM.Node.Types (Node)
import Data.Array (catMaybes, filter, head, range, reverse, sortWith)
import Data.Array as A
import Data.Foldable (any, foldMap, intercalate, null)
import Data.Fuzzy (FuzzyStr(..), matchStr)
import Data.Lens (_Just, (^.), (^?))
import Data.Lens.Record (prop)
import Data.Map as M
import Data.Maybe (Maybe(Just, Nothing), maybe)
import Data.Monoid (mempty)
import Data.Symbol (SProxy(..))
import Data.Traversable (traverse, traverse_)
import Data.Tuple (Tuple(..), snd)
import Fosskers.Common (Language(..), Path, _Path, _Title)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.CSS as HC
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Query.HalogenM as HQ
import Network.HTTP.Affjax (AJAX, get)
import Search as Search
import ServerAPI (getPosts)
import Types (Effects, Post, asPost, defaultLang, localizedDate, localizedPath, postLang, update)

---

data Query a = LangChanged Language a
             | NewKeywords (Array String) a
             | Selected Path a
             | HintChosen String a
             | Initialize a

type State = { language :: Language, posts :: Array Post, keywords :: Array String, selected :: Maybe Path }

data Slot = SearchSlot
derive instance eqSlot  :: Eq Slot
derive instance ordSlot :: Ord Slot

component :: forall e. H.Component HH.HTML Query Language Void (Effects e)
component = H.lifecycleParentComponent { initialState: const state
                                       , render
                                       , eval
                                       , receiver: HE.input LangChanged
                                       , initializer: Just $ Initialize unit
                                       , finalizer: Nothing }
  where state = { language: defaultLang, posts: mempty, keywords: mempty, selected: Nothing }

render :: forall e m. MonadEff ( dom :: DOM | e ) m => State -> H.ParentHTML Query Search.Query Slot m
render s = fluid [ HC.style <<< paddingTop $ pct 1.0 ]
           [ row_ [ HH.div [ HP.classes $ map H.ClassName [ "col-xs-12", "col-md-3" ]] $ selection s
                  , HH.div [ HP.classes $ map H.ClassName [ "col-xs-12", "col-md-6" ]] [ post ]
                  , HH.div [ HP.classes [ H.ClassName "col-md-3" ]] []
                  ]]

selection :: forall e m. MonadEff ( dom :: DOM | e ) m => State -> Array (H.ParentHTML Query Search.Query Slot m)
selection s = [ search ] <> hints s <> choices s
  where search = row_ [ col_ [ HH.slot SearchSlot Search.component s.language (HE.input NewKeywords) ] ]

hints :: forall c. State -> Array (HH.HTML c (Query Unit))
hints s | A.null s.keywords = []
        | otherwise = maybe [] f $ A.last s.keywords
  where ps = filter (\p -> postLang p == s.language) s.posts
        f kw | any (\p -> M.member kw p.freqs) ps = []
             | otherwise = let fuzzy = A.take 3
                                       $ A.sortWith (\(FuzzyStr z) -> z.distance)
                                       $ A.fromFoldable
                                       $ map (\k -> matchStr true kw k)
                                       $ M.keys
                                       $ foldMap _.freqs ps
                           in [ row [ HC.style $ paddingTop $ pct 1.0 ]
                                [ col_
                                  [ HH.text $ bool "もしかして：" "Perhaps you mean: " (s.language == English)
                                  , HH.div [ HP.class_ (H.ClassName "btn-toolbar")
                                           , HP.attr (H.AttrName "role") "toolbar"
                                           , HP.attr (H.AttrName "aria-label") "Hints" ]
                                    $ map (\(FuzzyStr z) -> hintButton z.original) fuzzy
                                  ]
                                ]
                              ]

hintButton :: forall c. String -> HH.HTML c (Query Unit)
hintButton s = HH.div [ HP.classes $ map H.ClassName ["btn-group", "mr-2"]
                      , HP.attr (H.AttrName "role") "group"
                      , HP.attr (H.AttrName "aria-label") $ "hint-" <> s ]
               [ HH.button [ HP.attr (H.AttrName "type") "button"
                           , HP.classes $ map H.ClassName [ "btn", "btn-outline-secondary", "btn-sm" ]
                           , HE.onClick (HE.input_ $ HintChosen s) ]
                 [ HH.text s ]
               ]

-- | Make a request for blog post content.
xhr :: forall e. String -> Aff ( ajax :: AJAX, dom :: DOM | e ) (Array Node)
xhr p = do
  res <- get $ "/blog/" <> p <> ".html"
  liftEff do
    parser <- newDOMParser
    let doc = parseHTMLFromString res.response parser
    body <- lastChild doc >>= (map join <<< traverse lastChild)
    maybe (pure []) children body

post :: forall c q. HH.HTML c q
post = HH.div [ HP.ref (H.RefLabel "blogpost") ] []

-- | If no keywords, rank by date. Otherwise, rank by "search hits".
choices :: forall c. State -> Array (HH.HTML c (Query Unit))
choices s = options (filter (\p -> postLang p == s.language) s.posts) >>= f
  where f p = let matches = map (\(Tuple k v) -> k <> " × " <> show v)
                            <<< reverse <<< sortWith snd <<< M.toUnfoldable $ hitsOnly p
              in [ row [ HC.style <<< paddingTop $ pct 1.0 ]
                   [ col_ [ HH.a [ HP.href "#"
                                 , HE.onClick $ const (Just $ Selected p.path unit) ]
                            [ HH.h5_ [ HH.text $ p.title ^. _Title ]]]]
                 , row_ $ [ HH.div [ HP.classes $ map H.ClassName [ "col-xs-12", "col-md-6" ] ]
                            [ HH.a [ HP.href $ "/blog/" <> p.path ^. _Path <> ".html"
                                   , HP.classes $ map H.ClassName [ "fas", "fa-link" ] ] []
                            , HH.i_ [ HH.text $ localizedDate s.language p.date ] ] ]
                   <> bool [] [ HH.div [ HP.classes $ map H.ClassName [ "col-xs-12", "col-md-6" ]]
                                [ HH.text $ intercalate ", " matches ]] (not $ null matches)
                 ]
        g p = any (\kw -> M.member kw p.freqs) s.keywords
        options ps | null s.keywords = ps
                   | otherwise = reverse <<< sortWith hitsOnly $ filter g ps
        hitsOnly p = M.filterKeys (\k -> A.elem k s.keywords) p.freqs

    -- H.lift <<< liftAff <<< log $ "Blog: New keywords -> " <> intercalate " " kws
eval :: forall e. Query ~> H.ParentDSL State Query Search.Query Slot Void (Effects e)
eval = case _ of
  NewKeywords kws next -> update (prop (SProxy :: SProxy "keywords")) kws *> pure next
  LangChanged l next   -> do
    curr <- H.gets _.language
    unless (l == curr) $ do
      H.modify (_ { language = l })
      choice <- H.gets _.selected
      traverse_ (\s -> eval $ Selected (localizedPath l s) unit) choice
    pure next
  Selected s next -> do
    curr <- H.gets _.selected
    unless (s ^? _Path == curr ^? _Just <<< _Path) $ do
      H.modify (_ { selected = Just s })
      htmls <- H.getHTMLElementRef (H.RefLabel "blogpost")
      traverse_ (\el -> liftAff (xhr $ s ^. _Path) >>= liftEff <<< replaceChildren el) htmls
    pure next
  HintChosen s next -> do
    void $ H.query SearchSlot $ H.action (Search.External s)
    pure next
  Initialize next -> do
    l <- H.gets _.language
    _ <- HQ.fork do
      rawPosts <- H.lift getPosts
      let posts = reverse <<< sortWith _.date <<< catMaybes $ map asPost rawPosts
      H.modify (_ { posts = posts })
      traverse_ (\p -> eval $ Selected p.path unit) <<< head $ filter (\p -> postLang p == l) posts
    pure next

replaceChildren :: forall e n m. IsNode n => IsNode m => n -> Array m -> Eff ( dom :: DOM | e ) Unit
replaceChildren el news = removeChildren el *> traverse_ (\n -> appendChild n el) news

removeChildren :: forall n e. IsNode n => n -> Eff ( dom :: DOM | e ) Unit
removeChildren el = children el >>= traverse_ (\n -> removeChild n el)

children :: forall n e. IsNode n => n -> Eff ( dom :: DOM | e ) (Array Node)
children el = do
  kids <- childNodes el
  len  <- length kids
  let ixs = range 0 (len - 1)
  catMaybes <$> traverse (\i -> item i kids) ixs
