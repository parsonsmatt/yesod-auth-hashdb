{-# LANGUAGE NoImplicitPrelude          #-}
{-# LANGUAGE OverloadedStrings          #-}

module IntegrationTest (
    withApp,
    integrationSpec
) where

import BasicPrelude
import Data.Aeson                   (FromJSON, parseJSON, (.:))
import qualified Data.Aeson as JSON
import Network.Wai.Test             (simpleBody)
import Test.Hspec                   (Spec, SpecWith, before,
                                     describe, it)
import qualified Yesod.Test as YT

import TestSite                     (App, Route(..))
import TestTools

type MyTestApp = YT.TestApp App
withApp :: App -> SpecWith (YT.TestApp App) -> Spec
withApp app = before $ return (app, id)

authUrl :: Text
authUrl = "http://localhost:3000/auth/login"

data AuthUrl = AuthUrl Text deriving (Eq, Show)
instance FromJSON AuthUrl where
    parseJSON (JSON.Object v) = AuthUrl <$> v .: "authentication_url"
    parseJSON _ = mempty

loginUrl :: Text
loginUrl = "http://localhost:3000/auth/page/hashdb/login"

data LoginUrl = LoginUrl Text deriving (Eq, Show)
instance FromJSON LoginUrl where
    parseJSON (JSON.Object v) = LoginUrl <$> v .: "loginUrl"
    parseJSON _ = mempty

successMsg :: Text
successMsg = "Login Successful"

data SuccessMsg = SuccessMsg Text deriving (Eq, Show)
instance FromJSON SuccessMsg where
    parseJSON (JSON.Object v) = SuccessMsg <$> v .: "message"
    parseJSON _ = mempty

getBodyJSON :: FromJSON a => YT.YesodExample site (Maybe a)
getBodyJSON = do
    resp <- YT.getResponse
    let body = simpleBody <$> resp
        result = JSON.decode =<< body
    return result

integrationSpec :: SpecWith MyTestApp
integrationSpec = do
    describe "The home page" $ do
      it "can be accessed" $ do
        YT.get HomeR
        YT.statusIs 200

    describe "The protected page" $ do
      it "requires login" $ do
        needsLogin GET ("/prot" :: Text)
      it "looks right after login by a valid user" $ do
        _ <- doLogin "paul" "MyPassword"
        YT.get ProtectedR
        YT.statusIs 200
        YT.bodyContains "OK, you are logged in so you are allowed to see this!"
      it "can't be accessed after login then logout" $ do
        _ <- doLogin "paul" "MyPassword"
        YT.get $ AuthR LogoutR
        -- That `get` will get the form from Yesod.Core.Handler.redirectToPost
        -- which will not be submitted automatically without javascript
        YT.bodyContains "please click on the button below to be redirected"
        -- so we do the redirection ourselves:
        YT.request $ do
            YT.setMethod "POST"
            YT.setUrl $ AuthR LogoutR
            -- yesod-core-1.4.19 added the CSRF token to the redirectToPost form
            YT.addToken
        YT.get HomeR
        YT.statusIs 200
        YT.bodyContains "Your current auth ID: Nothing"
        YT.get ProtectedR
        YT.statusIs 303

    describe "Login" $ do
      it "fails when incorrect password given" $ do
        loc <- doLoginPart1 "paul" "WrongPassword"
        checkFailedLogin loc
      it "fails when unknown user name given" $ do
        loc <- doLoginPart1 "xyzzy" "WrongPassword"
        checkFailedLogin loc

    describe "JSON Login" $ do
      it "JSON access to protected page gives JSON object with auth URL" $ do
        YT.request $ do
          YT.setMethod "GET"
          YT.setUrl ProtectedR
          YT.addRequestHeader ("Accept", "application/json")
        YT.statusIs 401
        auth <- getBodyJSON
        YT.assertEq "Authentication URL" auth (Just $ AuthUrl authUrl)
      it "Custom loginHandler using submitRouteHashDB has correct URL in JSON" $ do
        YT.request $ do
          YT.setMethod "GET"
          YT.setUrl authUrl
          YT.addRequestHeader ("Accept", "application/json")
        YT.statusIs 200
        login <- getBodyJSON
        YT.assertEq "Login URL" login (Just $ LoginUrl loginUrl)
      -- This example needs yesod-test >= 1.5.0.1, since older ones use wrong
      -- content type for JSON (https://github.com/yesodweb/yesod/issues/1063).
      it "Sending JSON username and password produces JSON success message" $ do
        -- This first request is only to get the CSRF token cookie, used below
        YT.request $ do
          YT.setMethod "GET"
          YT.setUrl authUrl
          YT.addRequestHeader ("Accept", "application/json")
        YT.request $ do
          YT.setMethod "POST"
          YT.setUrl loginUrl
          YT.addRequestHeader ("Accept", "application/json")
          YT.addRequestHeader ("Content-Type", "application/json; charset=utf-8")
          YT.setRequestBody "{\"username\":\"paul\",\"password\":\"MyPassword\"}"
          -- CSRF token is being checked, since yesod-core >= 1.4.14 is forced
          YT.addTokenFromCookie
        YT.statusIs 200
        msg <- getBodyJSON
        YT.assertEq "Login success" msg (Just $ SuccessMsg successMsg)
