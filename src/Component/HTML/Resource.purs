module Listasio.Component.HTML.Resource where

import Prelude

import Listasio.Component.HTML.Icons as Icons
import Data.Array (find, null)
import Data.Filterable (filter)
import Data.Maybe (isJust)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Listasio.Component.HTML.Tag as Tag
import Listasio.Component.HTML.Utils (maybeElem)
import Listasio.Data.List (ListWithIdUserAndMeta)
import Listasio.Data.Resource (ListResource)
import Tailwind as T
import Util (takeDomain)

resource :: forall i p. Array ListWithIdUserAndMeta -> ListResource -> HH.HTML i p
resource lists { url, title, list, completed_at } =
  HH.div
    [ HP.classes
        [ T.roundedMd
        , T.bgWhite
        , T.border2
        , T.borderKiwi
        , T.p2
        , T.flex
        , T.flexCol
        , T.justifyBetween
        ]
    ]
    [ HH.a
        [ HP.classes [ T.flex, T.itemsCenter ]
        , HP.href url
        , HP.target "_blank"
        , HP.rel "noreferrer noopener nofollow"
        ]
        [ HH.img [ HP.classes [ T.w4, T.h4, T.mr2 ], HP.src $ "https://s2.googleusercontent.com/s2/favicons?domain_url=" <> url ]
        , HH.div
            [ HP.classes
                [ T.textGray400
                , T.hoverTextKiwi
                , T.hoverUnderline
                , T.textSm
                , T.fontMedium
                , T.truncate
                ]
            ]
            [ HH.text title ]
        ]
    , shortUrl url
    , HH.div
        [ HP.classes [ T.flex, T.justifyBetween, T.itemsCenter, T.mt2 ] ]
        [ HH.div
            [ HP.classes [ T.flex ] ]
            [ HH.div
                [ HP.classes
                    [ T.textSm
                    , T.fontBold
                    , T.mr2
                    , T.w4
                    , T.textCenter
                    ]
                ]
                [ if isJust completed_at
                    then Icons.check [ Icons.classes [ T.textKiwi, T.h5, T.w5 ] ]
                    else HH.text ""
                ]
            , maybeElem (filter (not <<< null) $ map _.tags $ find ((list == _) <<< _.id) lists) \tags ->
                HH.div
                  [ HP.classes [ T.flex ] ]
                  $ map Tag.tag tags
            ]
        , maybeElem (find ((list == _) <<< _.id) lists) \l ->
            HH.div
              [ HP.classes [ T.textXs, T.mr2 ] ]
              [ HH.span [ HP.classes [ T.textGray200 ] ] [ HH.text "List: " ]
              , HH.span [ HP.classes [ T.textGray300, T.fontMedium ] ] [ HH.text l.title ]
              ]
        ]
    ]

shortUrl :: forall i p. String -> HH.HTML i p
shortUrl u =
  maybeElem (takeDomain u) \short ->
    HH.div
      [ HP.classes [ T.textGray300, T.textXs, T.mt2, T.ml6 ] ]
      [ HH.text short ]
