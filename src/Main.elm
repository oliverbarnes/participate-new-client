port module Main exposing (main)

import Html exposing (..)
import Html.Events exposing (..)
import Html.Attributes exposing (style, href, class, disabled, id)
import Material
import Material.Scheme
import Material.Button as Button
import Material.Textfield as Textfield
import Material.List as List
import Material.Options as Options exposing (css)
import Material.Layout as Layout
import Material.Color as Color
import Material.Menu as Menu
import Material.Elevation as Elevation
import Material.Grid as Grid exposing (grid, size, cell, Device(..))
import Material.Typography as Typography
import Material.Icon as Icon
import Material.Footer as Footer
import Material.Card as Card
import Material.Chip as Chip
import Material.Snackbar as Snackbar
import Material.Progress as Progress
import Form exposing (Form)
import Form.Field
import Form.Input
import Form.Error
import Form.Validate exposing (Validation)
import Dict exposing (Dict)
import Set exposing (Set)
import String
import Navigation exposing (Location)
import UrlParser exposing ((</>), (<?>))
import Http
import Types exposing (..)
import Config
import Api


-- ROUTES


type Route
    = Home
    | NewProposalRoute
    | ProposalRoute String
    | FacebookRedirect (Maybe String)
    | NotFoundRoute


routes : UrlParser.Parser (Route -> a) a
routes =
    UrlParser.oneOf
        [ UrlParser.map Home (UrlParser.top)
        , UrlParser.map NewProposalRoute (UrlParser.s "new-proposal")
        , UrlParser.map ProposalRoute (UrlParser.s "proposals" </> UrlParser.string)
        , UrlParser.map FacebookRedirect
            (UrlParser.s "facebook_redirect" <?> UrlParser.stringParam "code")
        ]


routeNeedsAccess : Route -> Bool
routeNeedsAccess route =
    case route of
        Home ->
            False

        FacebookRedirect _ ->
            False

        _ ->
            True



-- Port for storage of accessToken


port storeAccessToken : Maybe String -> Cmd msg



-- MODEL


type alias Model =
    { route : Route
    , accessToken : String
    , me : Me
    , form : Form () NewProposal
    , mdl : Material.Model
    , proposals : Dict String Proposal
    , snackbar : Snackbar.Model ()
    , progress : Bool
    }


initialModel : String -> Model
initialModel accessToken =
    { route = NotFoundRoute
    , accessToken = accessToken
    , me = { name = "" }
    , form = Form.initial [] validate
    , mdl = Material.model
    , proposals = Dict.empty
    , snackbar = Snackbar.model
    , progress = False
    }



-- UPDATE


type Msg
    = UrlChange Location
    | ApiMsg Api.Msg
    | NavigateToPath String
    | FormMsg Form.Msg
    | NoOp
    | Mdl (Material.Msg Msg)
    | SnackbarMsg (Snackbar.Msg ())
    | SupportProposal String Bool
    | SignOut


addProposal : Proposal -> Model -> Model
addProposal proposal model =
    { model | proposals = Dict.insert proposal.id proposal model.proposals }


addProposalList : ProposalList -> Model -> Model
addProposalList proposalList model =
    List.foldl addProposal model proposalList


withSnackbarNote : String -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
withSnackbarNote snackContent ( model, cmd ) =
    let
        ( snackModel, snackCmd ) =
            Snackbar.add
                (Snackbar.toast () snackContent)
                model.snackbar
    in
        ( { model | snackbar = snackModel }
        , Cmd.batch [ cmd, Cmd.map SnackbarMsg snackCmd ]
        )


withHttpErrorResponse : String -> Http.Error -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
withHttpErrorResponse contextText httpError ( model, cmd ) =
    withSnackbarNote
        (contextText ++ ": " ++ httpErrorToNoticeString httpError)
        ( model |> progressDone
        , Cmd.none
        )


httpErrorToNoticeString : Http.Error -> String
httpErrorToNoticeString httpError =
    case httpError of
        Http.BadStatus response ->
            response.status.message ++ " (" ++ toString response.status.code ++ ")"

        Http.BadPayload description _ ->
            "Bad payload (" ++ description ++ ")"

        Http.BadUrl description ->
            "Bad URL (" ++ description ++ ")"

        Http.Timeout ->
            "Timeout"

        Http.NetworkError ->
            "Network Error"


updateProposalSupport : Support -> Model -> Model
updateProposalSupport support model =
    let
        newProposals =
            Dict.update support.proposal
                (Maybe.map
                    (\proposal ->
                        { proposal
                            | supportCount = support.supportCount
                            , supportedByMe = support.supportedByMe
                        }
                    )
                )
                model.proposals
    in
        { model | proposals = newProposals }


subtractProposalSupport : String -> Model -> Model
subtractProposalSupport proposalId model =
    let
        newProposals =
            Dict.update proposalId
                (Maybe.map
                    (\proposal ->
                        { proposal
                            | supportCount = proposal.supportCount - 1
                            , supportedByMe = False
                        }
                    )
                )
                model.proposals
    in
        { model | proposals = newProposals }


progressStart : Model -> Model
progressStart model =
    { model | progress = True }


progressDone : Model -> Model
progressDone model =
    { model | progress = False }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlChange location ->
            let
                route =
                    UrlParser.parsePath routes location
                        |> Maybe.withDefault NotFoundRoute

                model1 =
                    { model | route = route }

                model1ps =
                    model1 |> progressStart

                _ =
                    Debug.log "UrlChange" ( route, location.href )
            in
                if String.isEmpty model.accessToken && routeNeedsAccess route then
                    ( model1ps, Navigation.newUrl "/" )
                else
                    case route of
                        FacebookRedirect maybeCode ->
                            ( model1ps
                            , case maybeCode of
                                Just code ->
                                    Api.authenticate code ApiMsg

                                Nothing ->
                                    Navigation.newUrl "/"
                            )

                        ProposalRoute id ->
                            case Dict.get id model.proposals of
                                Nothing ->
                                    ( model1ps
                                    , Api.getProposal id model.accessToken ApiMsg
                                    )

                                Just _ ->
                                    ( model1, Cmd.none )

                        Home ->
                            ( model1ps
                            , Api.getProposalList model.accessToken ApiMsg
                            )

                        _ ->
                            ( model1, Cmd.none )

        ApiMsg apiMsg ->
            case apiMsg of
                Api.GotAccessToken accessToken ->
                    ( { model | accessToken = accessToken }
                    , Cmd.batch
                        [ storeAccessToken (Just accessToken)
                        , Api.getMe accessToken ApiMsg
                        ]
                    )

                Api.AuthFailed httpError ->
                    withHttpErrorResponse
                        "Authentication failed"
                        httpError
                        ( model, Cmd.none )

                Api.GotMe me ->
                    ( { model | me = me } |> progressDone
                    , Navigation.newUrl "/"
                    )

                Api.ProposalCreated proposal ->
                    ( model
                        |> addProposal proposal
                    , Navigation.newUrl ("/proposals/" ++ proposal.id)
                    )
                        |> withSnackbarNote "Proposal saved"

                Api.ProposalCreationFailed httpError ->
                    withHttpErrorResponse
                        "Saving proposal failed"
                        httpError
                        ( model, Cmd.none )

                Api.ProposalSupported support ->
                    ( model |> updateProposalSupport support |> progressDone
                    , Cmd.none
                    )
                        |> withSnackbarNote "Proposal supported"

                Api.ProposalUnsupported proposalId ->
                    ( model |> subtractProposalSupport proposalId |> progressDone
                    , Cmd.none
                    )
                        |> withSnackbarNote "Proposal support withdrawn"

                Api.ToggleSupportFailed httpError ->
                    withHttpErrorResponse
                        "(Un-)Supporting proposal failed"
                        httpError
                        ( model, Cmd.none )

                Api.GotProposal proposal ->
                    ( model
                        |> addProposal proposal
                        |> progressDone
                    , Cmd.none
                    )

                Api.GettingProposalFailed httpError ->
                    withHttpErrorResponse
                        "Loading proposal failed"
                        httpError
                        ( model, Cmd.none )

                Api.GotProposalList proposalList ->
                    ( model
                        |> addProposalList proposalList
                        |> progressDone
                    , Cmd.none
                    )

                Api.GettingProposalListFailed httpError ->
                    withHttpErrorResponse
                        "Loading proposal list failed"
                        httpError
                        ( model, Cmd.none )

        NavigateToPath path ->
            ( model
            , Navigation.newUrl path
            )

        FormMsg formMsg ->
            case ( formMsg, Form.getOutput model.form ) of
                ( Form.Submit, Just proposalInput ) ->
                    model ! [ Api.createProposal proposalInput model.accessToken ApiMsg ]

                _ ->
                    ( { model | form = Form.update validate formMsg model.form }, Cmd.none )

        NoOp ->
            ( model, Cmd.none )

        Mdl mdlMsg ->
            Material.update Mdl mdlMsg model

        SnackbarMsg snackMsg ->
            -- Snackbar currently has no builtin elm-mdl-component support.
            -- Have to wire up manually here.
            -- https://github.com/debois/elm-mdl/blob/6340ec3c83875c35a5a89e7bf4408c1ca1cbfdcb/src/Material/Snackbar.elm#L311-L328
            let
                ( snackModel, snackCmd ) =
                    Snackbar.update snackMsg model.snackbar
            in
                ( { model | snackbar = snackModel }
                , Cmd.map SnackbarMsg snackCmd
                )

        SupportProposal id newState ->
            ( model |> progressStart
            , Api.toggleSupport id newState model.accessToken ApiMsg
            )

        SignOut ->
            ( { model | accessToken = "" }
            , Cmd.batch
                [ storeAccessToken Nothing
                , Navigation.newUrl "/"
                ]
            )


validate : Validation () NewProposal
validate =
    Form.Validate.map2 NewProposal
        (Form.Validate.field "title" Form.Validate.string)
        (Form.Validate.field "body" Form.Validate.string)



-- VIEW


type alias Mdl =
    Material.Model


view : Model -> Html Msg
view model =
    Layout.render Mdl
        model.mdl
        [ Layout.fixedHeader
        ]
        { header = viewHeader model
        , drawer = []
        , tabs = ( [], [] )
        , main = viewMain model
        }


viewHeader : Model -> List (Html Msg)
viewHeader model =
    [ Layout.row [ Color.background Color.white ] <|
        [ a
            [ href "/"
            , class "main-title"
            ]
            [ Layout.title [ Color.text <| Color.color Color.Cyan Color.S800 ]
                [ text "Participate!"
                ]
            ]
        , Layout.spacer
        ]
            ++ if String.isEmpty model.accessToken then
                [ viewLoginButton model ]
               else
                [ div [ class "mdl-layout--large-screen-only" ]
                    [ Button.render Mdl
                        [ 2 ]
                        model.mdl
                        [ Options.id "new-proposal"
                        , Button.colored
                        , Options.onClick <| NavigateToPath "/new-proposal"
                        ]
                        [ text "New proposal" ]
                    ]
                , viewUserNavigation model
                ]
    ]


viewLoginButton : Model -> Html Msg
viewLoginButton model =
    a [ href Api.facebookAuthUrl ]
        [ img
            [ Html.Attributes.src "/images/facebook-sign-in.png"
            , class "login-button-img"
            ]
            []
        ]


viewUserNavigation : Model -> Html Msg
viewUserNavigation model =
    let
        usernameColor =
            Color.text <| Color.color Color.Grey Color.S700
    in
        Layout.navigation []
            -- According to the mockup, the button should display user's avatar.
            -- But elm-mdl currently only supports icons for menu buttons.
            -- See: https://github.com/debois/elm-mdl/issues/165
            [ Menu.render Mdl
                [ 0 ]
                model.mdl
                [ Menu.ripple
                , Menu.bottomRight
                , Color.text <| Color.primary
                ]
                [ Menu.item
                    [ Menu.disabled, usernameColor ]
                    [ text "Signed in as" ]
                , Menu.item
                    [ Menu.divider, Menu.disabled, usernameColor ]
                    [ strong [] [ text model.me.name ] ]
                , Menu.item
                    [ Menu.onSelect <| NavigateToPath "/new-proposal" ]
                    [ text "New proposal" ]
                , Menu.item
                    [ Menu.onSelect SignOut ]
                    [ text "Sign out" ]
                ]
            ]


viewMain : Model -> List (Html Msg)
viewMain model =
    [ if model.progress then
        Progress.indeterminate
      else
        Progress.progress 0.0
    , case model.route of
        Home ->
            if String.isEmpty model.accessToken then
                viewLandingPage model
            else
                viewProposalList model

        NewProposalRoute ->
            viewNewProposal model

        ProposalRoute id ->
            div [] [ viewProposal model id ]

        NotFoundRoute ->
            div []
                [ text <| "Not found" ]

        FacebookRedirect _ ->
            div []
                [ text <| "Authenticating, please wait..." ]
    , viewFooter model
    , Snackbar.view model.snackbar |> Html.map SnackbarMsg
    ]


viewLandingPage : Model -> Html Msg
viewLandingPage model =
    div [ id "landing-pg" ]
        [ section [ id "hero" ]
            [ grid [ Options.cs "content-grid" ]
                [ cell [ size All 6, Typography.center ]
                    [ viewLoginButton model ]
                , cell [ size All 6 ]
                    [ Options.styled h1
                        [ Typography.display1
                        , Typography.contrast 1
                        , Color.text <| Color.color Color.Cyan Color.S800
                        ]
                        [ text "Participate!" ]
                    , Options.styled p
                        [ Typography.headline, Color.text <| Color.color Color.Cyan Color.S800 ]
                        [ text "An App for Democratic Decision Making" ]
                    ]
                ]
            ]
        , let
            feature icon text_ =
                cell [ size All 4, Typography.center ]
                    [ p [] [ Icon.i icon ]
                    , p [] [ text text_ ]
                    ]
          in
            section [ id "main-top" ]
                [ grid [ Options.cs "content-grid" ]
                    [ feature "assignment"
                        "A participant makes a proposal and gathers support for it. Other participants can collaborate on it if they support it in principle."
                    , feature "announcement"
                        "Dissenters have to make a counter-proposal, and gather support for it as well, to be heard."
                    , feature "call_merge"
                        "Representation is ensured for participants who are less involved through fluid delegation of support, in a liquid democracy."
                    ]
                ]
        , let
            feature turn title txt =
                grid [ Options.cs "content-grid" ] <|
                    (if turn then
                        List.reverse
                     else
                        identity
                    )
                        [ cell [ size All 6 ]
                            [ Options.styled p [ Typography.title ] [ text title ]
                            , p [] [ text txt ]
                            ]
                        , cell [ size All 6 ]
                            [ Options.div
                                [ Elevation.e2, Options.css "height" "150px" ]
                                []
                            ]
                        ]
          in
            section [ id "main-middle" ]
                [ feature True
                    "Concrete Proposals"
                    "Participate! focuses on concrete proposals rather than noisy and many times unproductive debate."
                , feature False
                    "Ensured Representation"
                    "Representation is ensured for participants who are less involved (be it for lack of time, inclination or of knowledge) through fluid delegation of support, in a liquid democracy."
                ]
        , Options.styled_ section
            [ Color.background <| Color.color Color.Grey Color.S200 ]
            [ id "main-lower" ]
            [ grid [ Options.cs "content-grid" ]
                [ cell [ size All 12, Typography.center ]
                    [ Options.styled h2
                        [ Typography.headline ]
                        [ text "Want to get involved?" ]
                    , p []
                        [ strong []
                            [ text "We pair program so you can get up to speed quickly and help us develop features"
                            ]
                        ]
                    , p []
                        [ a [ href "mailto:oliverbwork@gmail.com" ]
                            [ text "Shoot us an email"
                            ]
                        , text ", we'll add you to our Slack channel to join the discussion and talk about next steps."
                        ]
                    , p []
                        [ text "See the complete guide to contributing "
                        , a
                            [ href "https://github.com/participateapp/web-client/blob/master/CONTRIBUTING.md"
                            , Html.Attributes.target "_blank"
                            ]
                            [ text "here"
                            ]
                        , text "."
                        ]
                    ]
                ]
            ]
        ]


viewFooter : Model -> Html Msg
viewFooter model =
    Footer.mega []
        { top =
            Footer.top []
                { left =
                    Footer.left []
                        {-
                           -- elm-mdl has special functions for the footer contents, which we don't use here, because:
                           -- Class mdl-mega-footer__link-list puts the items to-to-down. We want them left-to-right.
                           -- Also, don't know how Footer.socialButton is supposed to work.
                           [ Footer.links [ Options.cs "social-links" ]
                               [ Footer.linkItem [ Footer.href "https://github.com/participateapp/web-client" ]
                                   [ Footer.html <|
                                       img [ Html.Attributes.src "/images/github-circle.png" ] []
                                   ]
                               , Footer.linkItem [ Footer.href "https://github.com/participateapp/web-client" ]
                                   [ Footer.html <|
                                       img [ Html.Attributes.src "/images/github-circle.png" ] []
                                   ]
                               ]
                           ]
                        -}
                        [ Footer.html <|
                            ul [ class "mdl-mini-footer__link-list social-links" ]
                                [ li []
                                    [ a [ Html.Attributes.href "https://github.com/participateapp/web-client" ]
                                        [ img [ Html.Attributes.src "/images/github-circle.png" ] [] ]
                                    ]
                                , li []
                                    [ a [ Html.Attributes.href "https://participateapp.slack.com" ]
                                        [ img [ Html.Attributes.src "/images/slack.png" ] [] ]
                                    ]
                                , li []
                                    [ a [ Html.Attributes.href "https://twitter.com/digiberber" ]
                                        [ img [ Html.Attributes.src "/images/twitter.png" ] [] ]
                                    ]
                                ]
                        ]
                , right =
                    Footer.right []
                        [ Footer.html <| Options.styled p [ Typography.title ] [ text "Participate!" ]
                        , Footer.html <| p [] [ text "An open source liquid democracy application." ]
                        ]
                }
        , middle = Nothing
        , bottom =
            Footer.bottom []
                [ Footer.html <|
                    ul [ class "mdl-mini-footer__link-list" ]
                        [ li []
                            [ a [ Html.Attributes.href "https://github.com/participateapp/web-client/blob/master/CONTRIBUTING.md" ]
                                [ text "Guide to contributing" ]
                            ]
                        , li []
                            [ a [ Html.Attributes.href "https://github.com/participateapp/web-client/wiki/Development-Setup" ]
                                [ text "Wiki" ]
                            ]
                        ]
                ]
        }


viewNewProposal : Model -> Html Msg
viewNewProposal model =
    Options.styled div
        [ Color.background <| Color.color Color.Grey Color.S200 ]
        [ div [ class "content-col narrow new-proposal-col" ]
            [ Card.view
                [ Options.cs "new-proposal"
                , Color.background <| Color.white
                ]
                [ Card.text []
                    [ titleField model
                    , bodyField model
                    ]
                , Card.text
                    [ Options.cs "mdl-grid" ]
                    [ Layout.spacer
                    , Button.render Mdl
                        [ 5 ]
                        model.mdl
                        [ Button.raised
                        , Button.ripple
                        , Button.colored
                        , Options.onClick <| FormMsg <| Form.Submit
                        ]
                        [ text "Save" ]
                    , Layout.spacer
                    ]
                ]
            ]
        ]


titleField : Model -> Html Msg
titleField model =
    let
        title =
            Form.getFieldAsString "title" model.form

        conditionalProperties =
            case title.liveError of
                Just error ->
                    case error of
                        Form.Error.InvalidString ->
                            [ Textfield.error "Can't be blank" ]

                        Form.Error.Empty ->
                            [ Textfield.error "Can't be blank" ]

                        _ ->
                            [ Textfield.error <| toString error ]

                Nothing ->
                    []
    in
        Textfield.render Mdl
            [ 0, 0 ]
            model.mdl
            ([ Textfield.label "Title"
             , Textfield.floatingLabel
             , Textfield.text_
             , Textfield.value <| Maybe.withDefault "" title.value
             , Options.onInput <| Form.Field.String >> Form.Input title.path Form.Text >> FormMsg
             , Options.onFocus <| FormMsg (Form.Focus title.path)
             , Options.onBlur <| FormMsg (Form.Blur title.path)
             ]
                ++ conditionalProperties
            )
            []


bodyField : Model -> Html Msg
bodyField model =
    let
        body =
            Form.getFieldAsString "body" model.form

        conditionalProperties =
            case body.liveError of
                Just error ->
                    case error of
                        Form.Error.InvalidString ->
                            [ Textfield.error "Can't be blank" ]

                        Form.Error.Empty ->
                            [ Textfield.error "Can't be blank" ]

                        _ ->
                            [ Textfield.error <| toString error ]

                Nothing ->
                    []
    in
        Textfield.render Mdl
            [ 0, 1 ]
            model.mdl
            ([ Textfield.label "Body"
             , Textfield.floatingLabel
             , Textfield.textarea
             , Textfield.rows 6
             , Textfield.value <| Maybe.withDefault "" body.value
             , Options.onInput <| Form.Field.String >> Form.Input body.path Form.Textarea >> FormMsg
             , Options.onFocus <| FormMsg (Form.Focus body.path)
             , Options.onBlur <| FormMsg (Form.Blur body.path)
             ]
                ++ conditionalProperties
            )
            []


viewProposal : Model -> String -> Html Msg
viewProposal model id =
    let
        cardContent =
            case Dict.get id model.proposals of
                Nothing ->
                    [ Card.title [] [ text "Unknown proposal id: ", text id ] ]

                Just proposal ->
                    [ Card.actions [ Options.cs "mdl-grid border-bottom" ]
                        [ span [ class "actions__authored" ]
                            [ img
                                [ class "mdl-chip__contact"
                                , Html.Attributes.src "/images/john.jpg"
                                ]
                                []
                            , span [ class "authored" ]
                                [ text proposal.author.name
                                , br [] []
                                , text "2 days ago"
                                ]
                            ]
                        , Layout.spacer
                        , Chip.span []
                            [ Chip.content []
                                [ text "Support count: "
                                , text <| toString proposal.supportCount
                                ]
                            ]
                        , Layout.spacer
                        , if proposal.authoredByMe then
                            Button.render Mdl
                                [ 3 ]
                                model.mdl
                                [ Options.id "support-proposal"
                                , Button.colored
                                , Button.accent
                                , Button.disabled
                                ]
                                [ text "Authored by me" ]
                          else
                            Button.render Mdl
                                [ 3 ]
                                model.mdl
                                ([ Options.id "support-proposal"
                                 , Button.colored
                                 , Options.onClick <| SupportProposal id (not proposal.supportedByMe)
                                 ]
                                    ++ if proposal.supportedByMe then
                                        [ Color.text <| Color.color Color.Green Color.S500 ]
                                       else
                                        [ Button.raised
                                        , Button.accent
                                        ]
                                )
                                [ text <|
                                    if proposal.supportedByMe then
                                        "Supporting"
                                    else
                                        "Support Proposal"
                                ]
                        ]
                    , Card.title []
                        [ Card.head
                            [ Typography.headline
                            , Color.text <| Color.color Color.Grey Color.S700
                            ]
                            [ text proposal.title ]
                        , Card.subhead
                            [ Typography.subhead ]
                            [ strong []
                                [ text "Here goes the summary, which is yet to be implemented ..." ]
                            ]
                        ]
                    , Card.text []
                        [ text proposal.body ]
                    ]
    in
        Options.styled div
            [ Color.background <| Color.color Color.Grey Color.S200 ]
            [ div [ class "content-col narrow proposal-col" ]
                [ Card.view
                    [ Options.cs "proposal-show"
                    , Color.background <| Color.white
                    ]
                    cardContent
                ]
            ]


viewProposalList : Model -> Html Msg
viewProposalList model =
    Options.styled div
        [ Color.background <| Color.color Color.Grey Color.S200 ]
        [ div [ class "content-col narrow proposal-list-col" ] <|
            List.map viewProposalListEntry (Dict.values model.proposals)
        ]


viewProposalListEntry : Proposal -> Html Msg
viewProposalListEntry proposal =
    Card.view
        [ Options.attribute <| onClick <| NavigateToPath <| "proposals/" ++ proposal.id
        , Color.background <| Color.white
        ]
        [ Card.title []
            [ div [ class "proposal-card-title" ]
                [ Card.head
                    [ Options.cs "proposal-title"
                    , Color.text <| Color.primary
                    ]
                    [ text proposal.title ]
                , div [ class "proposal-state" ]
                    [ div []
                        [ Chip.span
                            [ Typography.center
                            ]
                            [ Chip.text [] <| toString proposal.supportCount ]
                        ]
                    , if proposal.authoredByMe || proposal.supportedByMe then
                        Options.styled
                            span
                            [ Color.text <| Color.color Color.Green Color.S500 ]
                            [ text <|
                                if proposal.authoredByMe then
                                    "My Proposal"
                                else
                                    "Supporting"
                            ]
                      else
                        text ""
                    ]
                ]
            ]
        , Card.text [] [ text proposal.body ]
        ]



-- APP


type alias Flags =
    { accessToken : Maybe String }


init : Flags -> Location -> ( Model, Cmd Msg )
init flags location =
    let
        model0 =
            initialModel (Maybe.withDefault "" flags.accessToken)

        ( model1, cmd1 ) =
            update (UrlChange location) model0
    in
        ( model1
        , Cmd.batch
            [ cmd1
            , Layout.sub0 Mdl
            ]
        )


main : Program Flags Model Msg
main =
    Navigation.programWithFlags UrlChange
        { init = init
        , update = update
        , subscriptions =
            \model ->
                Sub.batch
                    [ Layout.subs Mdl model.mdl
                    , Menu.subs Mdl model.mdl
                    ]
        , view = view
        }
