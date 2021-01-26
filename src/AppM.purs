module Listasio.AppM where

import Prelude

import Control.Monad.Reader.Trans (class MonadAsk, ReaderT, ask, asks, runReaderT)
import Data.Array (filter, last, length, sortWith)
import Data.Codec.Argonaut as Codec
import Data.Codec.Argonaut.Compat as CAC
import Data.Codec.Argonaut.Record as CAR
import Data.DateTime (DateTime)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe, isJust, isNothing)
import Effect.Aff (Aff)
import Effect.Aff.Bus as Bus
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Console as Console
import Effect.Now as Now
import Effect.Ref as Ref
import Listasio.Api.Endpoint (Endpoint(..))
import Listasio.Api.Request (RequestMethod(..))
import Listasio.Api.Request as Request
import Listasio.Api.Utils (authenticate, decode, mkAuthRequest, mkRequest)
import Listasio.Capability.Clipboard (class Clipboard)
import Listasio.Capability.LogMessages (class LogMessages, logError)
import Listasio.Capability.Navigate (class Navigate, locationState, navigate)
import Listasio.Capability.Now (class Now)
import Listasio.Capability.Resource.List (class ManageList)
import Listasio.Capability.Resource.Resource (class ManageResource)
import Listasio.Capability.Resource.User (class ManageUser)
import Listasio.Data.List as List
import Listasio.Data.Log as Log
import Listasio.Data.Profile as Profile
import Listasio.Data.Resource as Resource
import Listasio.Data.ResourceMetadata as ResourceMeta
import Listasio.Data.Route as Route
import Listasio.Env (Env, LogLevel(..))
import Listasio.Foreign.Clipboard as ForeignClipboard
import Routing.Duplex (print)
import Type.Equality (class TypeEquals, from)
import Web.Event.Event (preventDefault)

newtype AppM a
  = AppM (ReaderT Env Aff a)

runAppM :: Env -> AppM ~> Aff
runAppM env (AppM m) = runReaderT m env

derive newtype instance functorAppM :: Functor AppM
derive newtype instance applyAppM :: Apply AppM
derive newtype instance applicativeAppM :: Applicative AppM
derive newtype instance bindAppM :: Bind AppM
derive newtype instance monadAppM :: Monad AppM
derive newtype instance monadEffectAppM :: MonadEffect AppM
derive newtype instance monadAffAppM :: MonadAff AppM

instance monadAskAppM :: TypeEquals e Env => MonadAsk e AppM where
  ask = AppM $ asks from

instance cliboardAppM :: Clipboard AppM where
  writeText = liftAff <<< ForeignClipboard.writeText

instance nowAppM :: Now AppM where
  now = liftEffect Now.now
  nowDate = liftEffect Now.nowDate
  nowTime = liftEffect Now.nowTime
  nowDateTime = liftEffect Now.nowDateTime

instance logMessagesAppM :: LogMessages AppM where
  logMessage log = do
    env <- ask
    liftEffect case env.logLevel, Log.reason log of
      Prod, Log.Debug -> pure unit
      _, _ -> Console.log $ Log.message log

instance navigateAppM :: Navigate AppM where
  locationState = liftEffect =<< _.nav.locationState <$> ask

  navigate route = do
    { pushState } <- asks _.nav
    { state } <- locationState
    liftEffect $ pushState state $ print Route.routeCodec $ route

  navigate_ event route = do
    liftEffect $ preventDefault event
    navigate route

  logout = do
    { currentUser, userBus } <- asks _.userEnv
    liftEffect do
      Ref.write Nothing currentUser
      Request.removeToken
    liftAff do
      Bus.write Nothing userBus
    navigate Route.Home

instance manageUserAppM :: ManageUser AppM where
  loginUser = authenticate Request.login

  googleLoginUser = authenticate Request.googleLogin unit

  registerUser fields = do
    { baseUrl } <- ask
    res <- Request.register baseUrl fields
    case res of
      Left err -> logError err *> pure Nothing
      Right profile -> pure $ Just profile

  getCurrentUser = do
    mbJson <- mkAuthRequest { endpoint: User, method: Get }
    map (map _.user)
      $ decode (CAR.object "User" { user: Profile.profileCodec }) mbJson

  updateUser fields =
    void
      $ mkAuthRequest
          { endpoint: User
          , method: Put $ Just $ Codec.encode Profile.profileCodec fields
          }

instance manageListAppM :: ManageList AppM where
  createList list =
    decode List.listWitIdAndUserCodec =<< mkAuthRequest conf
    where method = Post $ Just $ Codec.encode List.listCodec list
          conf = { endpoint: Lists, method }

  getList id =
    decode List.listWitIdAndUserCodec =<< mkAuthRequest conf
    where conf = { endpoint: List id, method: Get }

  getLists =
    decode (CAC.array List.listWitIdAndUserCodec) =<< mkAuthRequest conf
    where conf = { endpoint: Lists, method: Get }

  deleteList id = void $ mkAuthRequest { endpoint: List id, method: Delete }

  discoverLists pagination =
    decode (CAC.array List.listWitIdAndUserCodec) =<< mkRequest conf
    where conf = { endpoint: Discover pagination, method: Get }

instance manageResourceAppM :: ManageResource AppM where
  getMeta url = do
    decode ResourceMeta.metaCodec =<< mkAuthRequest conf
    where method = Post $ Just $ Codec.encode (CAR.object "Url" { url: Codec.string }) { url }
          conf = { endpoint: ResourceMeta, method }

  getListResources list = do
    mbResources <- decode (CAC.array Resource.listResourceCodec) =<< mkAuthRequest conf
    let total = fromMaybe 0 $ length <$> mbResources
        items = sortWith _.position <$> filter (isNothing <<< _.completed_at) <$> mbResources

        last_done :: Maybe DateTime
        last_done = _.completed_at =<< last =<< sortWith _.completed_at <$> filter (isJust <<< _.completed_at) <$> mbResources

        notRead = fromMaybe 0 $ length <$> items
        read = total - notRead
    pure $ (\is -> { items: is, total, read, last_done }) <$> items
    where conf = { endpoint: ResourcesByList { list }, method: Get }

  getResources = do
    decode (CAC.array Resource.listResourceCodec) =<< mkAuthRequest conf
    where conf = { endpoint: Resources, method: Get }

  createResource newResource =
    decode Resource.listResourceCodec =<< mkAuthRequest conf
    where method = Post $ Just $ Codec.encode Resource.resourceCodec newResource
          conf = { endpoint: Resources, method }

  completeResource { id } =
    map (const unit) <$> mkAuthRequest conf
    where conf = { endpoint: CompleteResource id, method: Post Nothing }

  deleteResource { id } =
    map (const unit) <$> mkAuthRequest conf
    where conf = { endpoint: Resource id, method: Delete }
