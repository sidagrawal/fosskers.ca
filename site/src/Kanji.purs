module Kanji where

import Prelude

import Bootstrap (col_, container, row, row_)
import CSS (paddingTop, pct)
import Control.Monad.Aff.AVar (AVAR)
import Control.Monad.Aff.Class (class MonadAff)
import Control.Monad.Eff.Exception (EXCEPTION)
import Control.Monad.Eff.Ref (REF)
import DOM (DOM)
import Data.Array (null)
import Data.Formatter.Number (Formatter(..), format)
import Data.Generic (gShow)
import Data.Int (ceil)
import Data.Kanji.Types (CharCat(Other, Punctuation, RomanLetter, Numeral, Katakana, Hiragana, Hanzi), Kanji(Kanji))
import Data.Lens ((^.))
import Data.Lens.Record (prop)
import Data.Maybe (Maybe(Just, Nothing), maybe)
import Data.String as S
import Data.Symbol (SProxy(..))
import Data.Traversable (traverse_)
import Data.Tuple (Tuple(Tuple))
import Data.Tuple.Nested ((/\))
import ECharts.Commands as E
import ECharts.Monad (DSL', interpret)
import ECharts.Types as ET
import ECharts.Types.Phantom as ETP
import Fosskers.Kanji (Analysis(Analysis))
import Halogen as H
import Halogen.ECharts as EC
import Halogen.HTML as HH
import Halogen.HTML.CSS as HC
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Query.HalogenM as HQ
import Network.HTTP.Affjax (AJAX)
import ServerAPI (getKanjiByText, postKanji)
import Types (Effects, Effects', Four(..), Language, defaultLang, update)

---

data Query a = LangChanged Language a
             | Update String a
             | ButtonSelected String a
             | HandleEChartsMsg EC.EChartsMessage a

type State = { language :: Language, analysis :: Maybe Analysis }

type Slot = Int

component :: forall e. H.Component HH.HTML Query Language Void (Effects e)
component = H.parentComponent { initialState: const { language: defaultLang, analysis: Nothing }
                              , render
                              , eval
                              , receiver: HE.input LangChanged }

render :: forall e. State -> H.ParentHTML Query EC.EChartsQuery Slot (Effects e)
render s = container [ HC.style <<< paddingTop $ pct 1.0 ]
           $ preamble <> buttons <> input <> maybe [] withResults s.analysis
  where preamble =
          [ row_ [ col_
                   [ HH.p_ [ HH.text "This is a demo of my "
                           , HH.a [ HP.href "http://hackage.haskell.org/package/kanji" ] [ HH.text "Kanji" ]
                           , HH.text $ " library for Haskell. Given Japanese text, it divides it into character "
                             <> "categories, and splits all "
                           , HH.a [ HP.href "https://en.wikipedia.org/wiki/Kanji" ] [ HH.text "漢字 (kanji)"]
                           , HH.text " into complexity/rarity "
                           , HH.i_ [ HH.text "Levels" ]
                           , HH.text " as defined by the "
                           , HH.a [ HP.href "http://www.kanken.or.jp/" ]
                             [ HH.text "Japan Kanji Aptitude Testing Foundation."]
                           ]
                   , HH.p_ [ HH.text $ "Try entering text below, or select one of the sample texts"
                             <> " to see how widely each Kanji level is used in real life."
                           ]]]]
        buttons = [ row_ [ col_
                           [ HH.div [ HP.class_ (H.ClassName "btn-toolbar")
                                    , HP.attr (H.AttrName "role") "toolbar"
                                    , HP.attr (H.AttrName "aria-label") "Sample Texts" ]
                             $ map button
                             [ Four "First Group" "primary" "doraemon" "Wikipedia: Doraemon"
                             , Four "Second Group" "warning" "sumo" "News: Asashoryu vs Hakoho"
                             , Four "Third Group" "success" "rashomon" "Short Story: Rashomon (1915)"
                             , Four "Last Group" "info" "iamacat" "Novel: I am a Cat (1905)"
                             ]]]]
        button (Four a c f t) = HH.div [ HP.classes $ map H.ClassName ["btn-group", "mr-2"]
                                       , HP.attr (H.AttrName "role") "group"
                                       , HP.attr (H.AttrName "aria-label") a ]
                               [ HH.button [ HP.attr (H.AttrName "type") "button"
                                           , HP.classes $ map H.ClassName [ "btn", "btn-outline-" <> c ]
                                           , HE.onClick (HE.input_ $ ButtonSelected f)
                                           ]
                                 [ HH.text t ]]
        input = [ row [ HC.style <<< paddingTop $ pct 1.0 ]
                  [ col_
                    [ HH.div [ HP.class_ (H.ClassName "input-group") ]
                      [ HH.div [ HP.class_ (H.ClassName "input-group-prepend") ]
                        [ HH.span [ HP.class_ (H.ClassName "input-group-text") ] [ HH.text "Input" ]]
                      , HH.textarea [ HP.class_ (H.ClassName "form-control")
                                    , HP.attr (H.AttrName "aria-label") "Input"
                                    , HE.onValueInput (\str -> Just $ Update str unit) ]]]]]
        withResults (Analysis a) = charts a <> unknowns a
        charts a = [ row [ HC.style <<< paddingTop $ pct 1.0 ]
                     [ col_ [ density $ a ^. prop (SProxy :: SProxy "density") ]]
                   , row [ HC.style <<< paddingTop $ pct 1.0 ] [ chart 0, chart 1 ]]
        unknowns a | null a.unknowns = [] -- = case M.lookup Unknown $ M.fromFoldable a.levelSplit of
                   | otherwise = [ HH.hr_ , HH.h5_ [ HH.text "Kanji of Unknown Level"], HH.div_ (map weblio a.unknowns) ]

chart :: forall t452 m e.
  MonadAff ( echarts :: ET.ECHARTS, dom :: DOM, avar :: AVAR, exception :: EXCEPTION, ref :: REF | e ) m
   => t452 -> HH.HTML (H.ComponentSlot HH.HTML EC.EChartsQuery m t452 (Query Unit)) (Query Unit)
chart n = HH.div [ HP.classes $ map HH.ClassName [ "col-xs-12", "col-md-6" ]]
          [ HH.slot n (EC.echarts Nothing) ({ width: 500, height: 350 } /\ unit)
            (Just <<< H.action <<< HandleEChartsMsg) ]

weblio :: forall t4 t5. Kanji -> HH.HTML t5 t4
weblio (Kanji k) = HH.a [ HP.href $ "https://weblio.jp/content/" <> k', HP.attr (H.AttrName "style") "float: left;" ] [ HH.h3_ [ HH.text k' ]]
  where k' = S.singleton k

density :: forall t340 t341. Array (Tuple CharCat Number) -> HH.HTML t341 t340
density d = HH.div [ HP.class_ $ H.ClassName "progress"
                   , HP.attr (H.AttrName "style") "height: 35px;" ] $
            map f d
  where f (Tuple c n) =
          let Tuple colour label = g c
              v = show <<< ceil $ n * 100.0
              v' = format form (n * 100.0)
          in HH.div [ HP.classes $ map H.ClassName [ "progress-bar", "progress-bar-striped", colour ]
                    , HP.attr (H.AttrName "role") "progressbar"
                    , HP.attr (H.AttrName "style") ("width: " <> v <> "%")
                    , HP.attr (H.AttrName "aria-valuenow") v
                    , HP.attr (H.AttrName "aria-valuemin") "0"
                    , HP.attr (H.AttrName "aria-valuemax") "100" ]
             [ HH.text $ v' <> "% " <> label ]
        g Hanzi       = Tuple "bg-info" "Kanji"
        g Hiragana    = Tuple "bg-success" "Hiragana"
        g Katakana    = Tuple "bg-warning" "Katakana"
        g Numeral     = Tuple "bg-primary" "Numbers"
        g RomanLetter = Tuple "bg-info" "Alphabet"
        g Punctuation = Tuple "bg-dark" "Punctuation"
        g Other       = Tuple "bg-secondary" "Other"
        form = Formatter { comma: false, before: 1, after: 1, abbreviations: false, sign: false }

-- これは日本語串糞猫牛虎山羊森林一二三

eval :: forall e. Query ~> H.ParentDSL State Query EC.EChartsQuery Slot Void (Effects' ( ajax :: AJAX | e ))
eval = case _ of
  LangChanged l next -> update (prop (SProxy :: SProxy "language")) l *> pure next
  Update "" next -> H.modify (_ { analysis = Nothing }) *> pure next
  Update s next -> do
    _ <- HQ.fork do
      a <- H.lift $ postKanji s
      updateCharts a
      H.modify (_ { analysis = Just a })
    pure next
  HandleEChartsMsg EC.Initialized next ->
    (H.gets _.analysis >>= maybe (pure unit) updateCharts) *> pure next
  HandleEChartsMsg (EC.EventRaised evt) next -> pure next
  ButtonSelected t next -> do
    _ <- HQ.fork do
      a <- H.lift $ getKanjiByText t
      maybe (pure unit) updateCharts a
      H.modify (_ { analysis = a })
    pure next

updateCharts :: forall t800 t801 t804 t805. Analysis -> H.HalogenM t805 t804 EC.EChartsQuery Int t801 t800 Unit
updateCharts a = when (hasRealData a) do
  void $ H.query 0 $ H.action $ EC.Set $ interpret $ byLevel a
  void $ H.query 1 $ H.action $ EC.Set $ interpret $ lifeStages a

hasRealData :: Analysis -> Boolean
hasRealData (Analysis a) = not $ null a.distributions

byLevel :: Analysis -> DSL' ETP.OptionI
byLevel (Analysis a) = do
  E.tooltip do
    E.trigger ET.ItemTrigger
    E.formatterString "{b} <br /> {d}%"
  E.title do
    E.text "Level Distributions"
    E.subtext "Percentage of Kanji per Level"
  E.series do
    E.pie do
      E.name "Levels"
      E.center $ ET.Point { x: ET.Percent 50.0, y: ET.Percent 60.0 }
      E.selectedMode ET.Single
      E.buildItems $
        traverse_ (\(Tuple l n) -> E.addItem $ E.value n *> E.name (S.drop 17 $ gShow l)) a.distributions

lifeStages :: Analysis -> DSL' ETP.OptionI
lifeStages (Analysis a) = do
  E.tooltip do
    E.trigger ET.ItemTrigger
    E.formatterString "{b} <br /> {d}%"
  E.title do
    E.text "Kanji by Life Stages"
    E.subtext "Percentage of Kanji learned by different life stages"
  E.series do
    E.pie do
      E.name "Kanji"
      E.center $ ET.Point { x: ET.Percent 50.0, y: ET.Percent 60.0 }
      E.selectedMode ET.Single
      E.buildItems do
        E.addItem $ E.value a.elementary *> E.name "Elementary Shcool"
        E.addItem $ E.value (a.middle - a.elementary) *> E.name "Middle School"
        E.addItem $ E.value (a.high - a.middle) *> E.name "High School"
        E.addItem $ E.value (a.adult - a.high) *> E.name "Adult"
        E.addItem $ E.value (1.0 - a.adult) *> E.name "Higher"
