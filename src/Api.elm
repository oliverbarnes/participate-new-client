module Api exposing (tokenUrl, fbAuthUrl, Msg(..), authenticateCmd, postJson)

import Http
import Task exposing (Task)
import Json.Decode as Decode
import Json.Decode exposing (Decoder)


apiRoot : String
apiRoot = "http://localhost:4000"

tokenUrl : String
tokenUrl = apiRoot ++ "/token"

-- TODO: move client_id and redirect_uri into environment variables
fbAuthUrl : String
fbAuthUrl = "https://www.facebook.com/dialog/oauth?client_id=1583083701926004&redirect_uri=http://localhost:3000/"


-- MESSAGES

type Msg
  = GotAccessToken String
  | AuthFailed Http.Error


accessTokenDecoder : Decoder String
accessTokenDecoder =
  Decode.at ["access_token"] Decode.string


authenticateCmd : (Msg -> a) -> String -> Cmd a
authenticateCmd wrapFn authCode =
  let
    body =
      "{\"auth_code\": \"" ++ authCode ++ "\"}"
    
    requestTask =
      postJson accessTokenDecoder tokenUrl body
  in
    Task.perform AuthFailed GotAccessToken requestTask
      |> Cmd.map wrapFn


postJsonWithHeaders : List (String, String) -> Decoder a -> String -> String -> Task Http.Error a
postJsonWithHeaders headers responseDecoder url jsonBody =
  { verb = "POST", headers = [("Content-Type", "application/json")] ++ headers, url = url, body = Http.string jsonBody }
    |> Http.send Http.defaultSettings
    |> Http.fromJson responseDecoder

postJson : Decoder a -> String -> String -> Task Http.Error a
postJson =
  postJsonWithHeaders []
