module Listasio.Component.HTML.CreateResource where

import Prelude

import Data.Array (sortWith)
import Data.Char.Unicode as Char
import Data.Filterable (filter)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.MediaType.Common as MediaType
import Data.Newtype (class Newtype, unwrap)
import Data.Symbol (SProxy(..))
import Data.String.CodeUnits as String
import Data.Traversable (traverse)
import Effect.Aff.Class (class MonadAff)
import Formless as F
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Listasio.Capability.Resource.Resource (class ManageResource, createResource, getMeta)
import Listasio.Component.HTML.Dropdown as DD
import Listasio.Component.HTML.Resource as ResourceComponent
import Listasio.Component.HTML.Utils (maybeElem, whenElem)
import Listasio.Data.ID (ID)
import Listasio.Data.List (ListWithIdAndUser)
import Listasio.Data.Resource (ListResource, Resource)
import Listasio.Data.ResourceMetadata (ResourceMeta)
import Listasio.Form.Field as Field
import Listasio.Form.Validation (class ToText, (<?>))
import Listasio.Form.Validation as V
import Network.RemoteData (RemoteData(..), isFailure, isLoading, isSuccess)
import Select as Select
import Tailwind as T
import Util as Util
import Web.Clipboard.ClipboardEvent as Clipboard
import Web.Event.Event as Event
import Web.HTML.Event.DataTransfer as DataTransfer

type Slot = forall query. H.Slot query Output Unit

_createResource = SProxy :: SProxy "createResource"

data Action
  = HandleFormMessage Resource

type State
  = { lists :: Array ListWithIdAndUser
    , url :: Maybe String
    }

type Input
  = { lists :: Array ListWithIdAndUser
    , url :: Maybe String
    }

data Output
  = Created ListResource

type ChildSlots
  = ( formless :: FormSlot )

filterNonAlphanum :: String -> String
filterNonAlphanum =
  String.fromCharArray <<< filter Char.isAlphaNum <<< String.toCharArray

component :: forall query m.
     MonadAff m
  => ManageResource m
  => H.Component HH.HTML query Input Output m
component = H.mkComponent
  { initialState
  , render
  , eval: H.mkEval $ H.defaultEval
      { handleAction = handleAction
      }
  }
  where
  initialState { lists, url } =
    { lists: sortWith (filterNonAlphanum <<< _.title) lists
    , url
    }

  handleAction :: Action -> H.HalogenM State Action ChildSlots Output m Unit
  handleAction = case _ of
    HandleFormMessage newResource -> do
      void $ H.query F._formless unit $ F.injQuery $ SetCreateStatus Loading unit

      mbNewResource <- createResource newResource

      case mbNewResource of
        Just resource -> do
          H.raise $ Created resource
          void $ H.query F._formless unit $ F.injQuery $ SetCreateStatus (Success unit) unit

        Nothing ->
          void $ H.query F._formless unit $ F.injQuery $ SetCreateStatus (Failure "Could not create resource") unit

  render :: State -> HH.ComponentHTML Action ChildSlots m
  render { lists, url } =
    HH.div
      []
      [ HH.slot F._formless unit formComponent { lists, url } (Just <<< HandleFormMessage) ]

newtype DDItem = DDItem { label :: String, value :: ID }

derive instance eqDDItem :: Eq DDItem
derive instance newtypeDDItem :: Newtype DDItem _

instance toTextDDItem :: ToText DDItem where
  toText = _.label <<< unwrap

type FormSlot
  = F.Slot CreateResourceForm FormQuery FormChildSlots Resource Unit

newtype CreateResourceForm r f
  = CreateResourceForm
  ( r
      ( title :: f V.FormError String String
      , url :: f V.FormError String String
      , description :: f V.FormError String (Maybe String)
      , thumbnail :: f V.FormError (Maybe String) (Maybe String)
      , list :: f V.FormError (Maybe ID) ID
      )
  )

derive instance newtypeCreateResourceForm :: Newtype (CreateResourceForm r f) _

data FormQuery a
  = SetCreateStatus (RemoteData String Unit) a

derive instance functorFormQuery :: Functor FormQuery

data FormAction
  = FormInitialize
  | Submit Event.Event
  | HandleDropdown (DD.Message DDItem)
  | FetchMeta String
  | PasteUrl Clipboard.ClipboardEvent

type FormInput
  = { lists :: Array ListWithIdAndUser
    , url :: Maybe String
    }

type FormChildSlots = ( dropdown :: DD.Slot DDItem Unit )

type FormState =
  ( status :: RemoteData String Unit
  , meta :: RemoteData String ResourceMeta
  , pastedUrl :: Maybe String
  , lists :: Array ListWithIdAndUser
  )

formComponent ::
  forall m.
  MonadAff m =>
  ManageResource m =>
  F.Component CreateResourceForm FormQuery FormChildSlots FormInput Resource m
formComponent = F.component formInput $ F.defaultSpec
  { render = renderCreateResource
  , handleEvent = handleEvent
  , handleQuery = handleQuery
  , handleAction = handleAction
  , initialize = Just FormInitialize
  }
  where
  formInput :: FormInput -> F.Input CreateResourceForm FormState m
  formInput { lists, url } =
    { validators:
        CreateResourceForm
          { title: V.required >>> V.maxLength 150
          , url: V.required >>> V.maxLength 500 -- TODO URL validation ???
          , description:  V.toOptional $ V.maxLength 500
          , thumbnail: F.noValidation
          , list: V.requiredFromOptional F.noValidation
                   <?> V.WithMsg "Please select a list"
          }
    , initialInputs: Just $ initialInputs url
    , status: NotAsked
    , meta: NotAsked
    , lists
    , pastedUrl: url
    }

  initialInputs url = F.wrapInputFields
    { url: fromMaybe "" url
    , title: ""
    , description: ""
    , thumbnail: Nothing
    , list: Nothing
    }

  handleEvent = F.raiseResult

  handleAction = case _ of
    FormInitialize -> do
      { pastedUrl } <- H.get
      case pastedUrl of
        Just url -> handleAction $ FetchMeta url
        Nothing -> pure unit

    PasteUrl event -> do
      mbUrl <- H.liftEffect $ filter Util.isUrl <$> traverse (DataTransfer.getData MediaType.textPlain) (Clipboard.clipboardData event)
      case mbUrl of
        Just url -> handleAction $ FetchMeta url
        Nothing -> pure unit

    FetchMeta url -> do
      H.modify_ _ { meta = Loading }
      mbMeta <- getMeta url
      case mbMeta of
        Just meta -> do
          H.modify_ _ { meta = Success meta }
          eval $ F.setValidate proxies.thumbnail meta.thumbnail
          case meta.title of
            Just title -> eval $ F.setValidate proxies.title title
            Nothing -> pure unit
          case meta.description of
            Just description -> eval $ F.setValidate proxies.description description
            Nothing -> pure unit
        Nothing ->
          H.modify_ _ { meta = Failure "Couldn't gett suggestions" }

    Submit event -> do
      { status } <- H.get
      when (not $ isLoading status) do
        H.liftEffect $ Event.preventDefault event
        eval F.submit

    HandleDropdown (DD.Selected (DDItem { value })) ->
      eval $ F.setValidate proxies.list (Just value)

    HandleDropdown DD.Cleared ->
      eval $ F.setValidate proxies.list Nothing

    where
    eval act = F.handleAction handleAction handleEvent act

  handleQuery :: forall a. FormQuery a -> H.HalogenM _ _ _ _ _ (Maybe a)
  handleQuery = case _ of
    SetCreateStatus status a -> do
      H.modify_ _ { status = status }
      when (isSuccess status) do
        eval F.resetAll
        void $ H.query DD._dropdown unit DD.clear
      pure $ Just a

    where
    eval act = F.handleAction handleAction handleEvent act

  proxies = F.mkSProxies (F.FormProxy :: _ CreateResourceForm)

  renderCreateResource { form, status, lists, submitting, dirty, meta } =
    HH.form
      [ HE.onSubmit $ Just <<< F.injAction <<< Submit ]
      [ whenElem (isFailure status) \_ ->
          HH.div
            []
            [ HH.text "Failed to add resource" ]
      , HH.fieldset
          []
          [ Field.input (Just "Link") proxies.url form
              [ HP.placeholder "https://blog.com/some-blogpost"
              , HP.type_ HP.InputText
              , HE.onPaste $ Just <<< F.injAction <<< PasteUrl
              ]

          , case meta of
              Loading ->
                HH.div
                  [ HP.classes [ T.textSm, T.pt2, T.textGray300 ] ]
                  [ HH.text "Fetching title and description ..." ]

              Success {can_resolve} | not can_resolve ->
                HH.div
                  [ HP.classes [ T.textSm, T.pt2, T.textManzana ] ]
                  [ HH.text "Looks like the link does not exist. Are you sure you got the right one?" ]

              Success {resource: Just resource} ->
                HH.div
                  [ HP.classes [ T.mt2, T.mb4 ] ]
                  [ HH.div
                      [ HP.classes [ T.textManzana, T.textSm, T.mb2 ] ]
                      [ HH.text "This resource already exists. Are you sure you want to add it again?" ]
                  , ResourceComponent.resource lists resource
                  ]

              _ ->
                HH.text ""

          , HH.div
              [ HP.classes [ T.mt4 ] ]
              [ HH.div
                  [ HP.classes [ T.mb2 ] ]
                  [ HH.label
                    [ HP.classes [ T.textGray400, T.textLg ] ]
                    [ HH.text "List" ]
                  ]
              , HH.slot DD._dropdown unit (Select.component DD.input DD.spec) ddInput handler
              , let mbError = filter (const $ F.getTouched proxies.list form) $ F.getError proxies.list form
                 in maybeElem mbError \err ->
                      HH.div
                        [ HP.classes [ T.textManzana, T.mt2 ] ]
                        [ HH.text $ V.errorToString err ]
              ]

          , HH.div
              [ HP.classes [ T.flex, T.spaceX4 ] ]
              [ HH.div
                  [ HP.classes[ T.w40, T.h40, T.mt14 ]
                  ]
                  [ case meta of
                      Success {thumbnail: Just thumbnail} ->
                        HH.img
                          [ HP.src thumbnail
                          , HP.classes [ T.w40, T.h40, T.objectCover, T.roundedLg ]
                          ]

                      Loading ->
                        HH.div
                          [ HP.classes
                              [ T.w40
                              , T.h40
                              , T.flex
                              , T.flexCol
                              , T.justifyCenter
                              , T.itemsCenter
                              , T.textGray400
                              , T.bgGray100
                              , T.roundedLg
                              , T.text4xl
                              ]
                          ]
                          [ HH.text "⌛" ]

                      _ ->
                        HH.div
                          [ HP.classes
                              [ T.w40
                              , T.h40
                              , T.flex
                              , T.flexCol
                              , T.justifyCenter
                              , T.itemsCenter
                              , T.textGray400
                              , T.bgGray100
                              , T.roundedLg
                              , T.text4xl
                              ]
                          ]
                          [ HH.text "404" ]
                  ]
              , HH.div
                  []
                  [ HH.div
                      [ HP.classes [ T.mt4 ] ]
                      [ Field.input (Just "Title") proxies.title form
                          [ HP.placeholder "Some blogpost"
                          , HP.type_ HP.InputText
                          ]
                      ]
                  , HH.div
                      [ HP.classes [ T.mt4 ] ]
                      [ Field.textarea (Just "Description") proxies.description form
                          [ HP.placeholder "Such description. Much wow."
                          , HP.rows 2
                          ]
                      ]
                  ]
              ]

          , whenElem (isFailure status) \_ ->
              HH.div
                [ HP.classes [ T.textRed500, T.my4 ] ]
                [ HH.text "Could not create resource :(" ]

          , HH.div
              [ HP.classes [ T.mt4 ] ]
              [ Field.submit "Add resource" (submitting || isLoading status) ]
          ]
      ]
    where handler = Just <<< F.injAction <<< HandleDropdown
          listToItem { id, title } = DDItem { value: id, label: title }
          ddInput = { placeholder: "Choose a list", items: map listToItem lists }
