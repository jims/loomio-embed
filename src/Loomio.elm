module Loomio exposing (AvatarSize(..), Collection(..), Comment, DiscussionInfo, User, UserDict, apiUrl, avatarPixelSize, decodeComment, decodeComments, decodeDiscussion, decodeUploadedAvatarUrls, decodeUser, decodeUsers, gravatarUrls, userAvatarUrl)

import Dict exposing (Dict)
import Json.Decode as Json exposing (andThen, at, fail, field, int, list, map, map2, map3, map4, maybe, string, succeed)
import List exposing (filter, head)
import Tuple
import Url
import Url.Builder


type alias User =
    { name : String
    , username : Maybe String
    , avatarUrls : Maybe ( Url.Url, Url.Url, Url.Url )
    }


type alias Comment =
    { body : String
    , createdAt : String
    , updatedAt : String
    , user : User
    }


type alias DiscussionInfo =
    { id : Int
    , numComments : Int
    }


type alias UserDict =
    Dict Int User


type AvatarSize
    = Small
    | Medium
    | Large


avatarPixelSize s =
    case s of
        Small ->
            30

        Medium ->
            50

        Large ->
            170


userAvatarUrl : AvatarSize -> User -> Maybe Url.Url
userAvatarUrl sz user =
    user.avatarUrls
        |> Maybe.map
            (\( s, m, l ) ->
                case sz of
                    Small ->
                        s

                    Medium ->
                        m

                    Large ->
                        l
            )


type Collection
    = Discussions
    | Events


apiUrl : Url.Url -> Collection -> Maybe String -> List Url.Builder.QueryParameter -> Url.Url
apiUrl base collection id params =
    let
        collectionName =
            case collection of
                Discussions ->
                    "discussions"

                Events ->
                    "events"

        collectionId =
            id
                |> Maybe.map (String.append "/")
                |> Maybe.withDefault ""
    in
    { base
        | path = "/api/v1/" ++ collectionName ++ collectionId
        , query = Just <| String.dropLeft 1 <| Url.Builder.toQuery params
    }


decodeDiscussion : Json.Decoder DiscussionInfo
decodeDiscussion =
    map2 DiscussionInfo
        (field "id" int)
        (field "items_count" int)


decodeComments : Url.Url -> Json.Decoder (List Comment)
decodeComments baseUrl =
    field "users" (decodeUsers baseUrl)
        |> andThen (\u -> field "comments" <| list (decodeComment u))


decodeComment : UserDict -> Json.Decoder Comment
decodeComment users =
    map4 Comment
        (field "body" string)
        (field "created_at" string)
        (field "updated_at" string)
        (field "author_id" int
            |> andThen
                (\id ->
                    case Dict.get id users of
                        Nothing ->
                            fail "Unknown user"

                        Just u ->
                            succeed u
                )
        )


decodeUploadedAvatarUrls : Url.Url -> Json.Decoder (Maybe ( Url.Url, Url.Url, Url.Url ))
decodeUploadedAvatarUrls baseUrl =
    let
        triple a b c =
            ( a, b, c )

        urlPathString =
            map (\p -> Just { baseUrl | path = p }) string
    in
    map3 triple
        (field "small" urlPathString)
        (field "medium" urlPathString)
        (field "large" urlPathString)
        |> map
            (\( s, m, l ) ->
                Maybe.map3 triple s m l
            )


gravatarUrls : String -> ( Url.Url, Url.Url, Url.Url )
gravatarUrls emailHash =
    let
        url s =
            { protocol = Url.Https
            , host = "www.gravatar.com"
            , port_ = Nothing
            , path = "/avatar/" ++ emailHash
            , query = Just <| String.dropLeft 1 <| Url.Builder.toQuery [ Url.Builder.int "s" (avatarPixelSize s) ]
            , fragment = Nothing
            }
    in
    ( url Small, url Medium, url Large )


decodeUsers : Url.Url -> Json.Decoder UserDict
decodeUsers baseUrl =
    map2
        Tuple.pair
        (field "id" int)
        (decodeUser baseUrl)
        |> list
        |> map Dict.fromList


decodeUser : Url.Url -> Json.Decoder User
decodeUser baseUrl =
    map3 User
        (field "name" string)
        (field "username" (maybe string))
        (field "avatar_kind" string
            |> andThen
                (\kind ->
                    case kind of
                        "uploaded" ->
                            field "avatar_url" (decodeUploadedAvatarUrls baseUrl)

                        "gravatar" ->
                            field "email_hash" (string |> map gravatarUrls |> map Just)

                        _ ->
                            succeed Nothing
                )
        )
