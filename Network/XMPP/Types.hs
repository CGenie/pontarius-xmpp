-- Copyright © 2010-2011 Jon Kristensen. See the LICENSE file in the Pontarius
-- XMPP distribution for more details.

{-# OPTIONS_HADDOCK hide #-}

{-# LANGUAGE MultiParamTypeClasses #-}

module Network.XMPP.Types (
StanzaID (..),
From,
To,
IQ (..),
IQRequest (..),
IQResponse (..),
Message (..),
MessageType (..),
Presence (..),
PresenceType (..),
StanzaError (..),
StanzaErrorType (..),
StanzaErrorCondition (..),
                            HostName
                            , Password
                            , PortNumber
                            , Resource
                            , UserName,
EnumeratorEvent (..),
Challenge (..),
Success (..),
TLSState (..),
Address (..),
Localpart,
Domainpart,
Resourcepart,
XMLLang,
InternalEvent (..),
XMLEvent (..),
ConnectionState (..),
ClientEvent (..),
StreamState (..),
AuthenticationState (..),
ConnectResult (..),
OpenStreamResult (..),
SecureWithTLSResult (..),
AuthenticateResult (..),
ServerAddress (..),
XMPPError (..),
Timeout,
TimeoutEvent (..),
StreamError (..),
IDGenerator (..)
) where

import GHC.IO.Handle (Handle, hPutStr, hFlush, hSetBuffering, hWaitForInput)

import qualified Network as N

import qualified Control.Exception as CE

import Control.Monad.State hiding (State)

import Data.XML.Types

import Network.TLS
import Network.TLS.Cipher

import qualified Control.Monad.Error as CME

import Data.IORef

import Data.Certificate.X509 (X509)


-- =============================================================================
--  STANZA TYPES
-- =============================================================================


-- TODO: Would a Stanza class such as the one below be useful sometimes?
--
-- class Stanza a where
--     stanzaID :: a -> Maybe StanzaID
--     stanzaFrom :: a -> Maybe From
--     stanzaTo :: a -> Maybe To
--     stanzaXMLLang :: a -> Maybe XMLLang


-- |
-- The StanzaID type wraps a string of random characters that in Pontarius XMPP
-- is guaranteed to be unique for the XMPP session. Clients can add a string
-- prefix for the IDs to guarantee that they are unique in a larger context by
-- specifying the stanzaIDPrefix setting. TODO

data StanzaID = SID String deriving (Eq, Show)


-- |
-- @From@ is a readability type synonym for @Address@.

type From = Address


-- |
-- @To@ is a readability type synonym for @Address@.

type To = Address


-- |
-- An Info/Query (IQ) stanza is either of the type "request" ("get" or "set") or
-- "response" ("result" or "error"). The @IQ@ type wraps these two sub-types.

data IQ = IQReq IQRequest | IQRes IQResponse deriving (Eq, Show)


-- |
-- A "request" Info/Query (IQ) stanza is one with either "get" or "set" as type.
-- They are guaranteed to always contain a payload.

data IQRequest = IQGet { iqRequestID :: Maybe StanzaID
                       , iqRequestFrom :: Maybe From
                       , iqRequestTo :: Maybe To
                       , iqRequestXMLLang :: Maybe XMLLang
                       , iqRequestPayload :: Element } |
                 IQSet { iqRequestID :: Maybe StanzaID
                       , iqRequestFrom :: Maybe From
                       , iqRequestTo :: Maybe To
                       , iqRequestXMLLang :: Maybe XMLLang
                       , iqRequestPayload :: Element }
                 deriving (Eq, Show)


-- |
-- A "response" Info/Query (IQ) stanza is one with either "result" or "error" as
-- type.

data IQResponse = IQResult { iqResponseID :: Maybe StanzaID
                           , iqResponseFrom :: Maybe From
                           , iqResponseTo :: Maybe To
                           , iqResponseXMLLang :: Maybe XMLLang
                           , iqResponsePayload :: Maybe Element } |
                  IQError { iqResponseID :: Maybe StanzaID
                          , iqResponseFrom :: Maybe From
                          , iqResponseTo :: Maybe To
                          , iqResponseXMLLang :: Maybe XMLLang
                          , iqResponsePayload :: Maybe Element
                          , iqResponseStanzaError :: StanzaError }
                  deriving (Eq, Show)


-- |
-- The message stanza - either a message or a message error.

data Message = Message { messageID :: Maybe StanzaID
                       , messageFrom :: Maybe From
                       , messageTo :: Maybe To
                       , messageXMLLang :: Maybe XMLLang
                       , messageType :: MessageType
                       , messagePayload :: [Element] } |
               MessageError { messageID :: Maybe StanzaID
                            , messageFrom :: Maybe From
                            , messageTo :: Maybe To
                            , messageXMLLang  :: Maybe XMLLang
                            , messageErrorPayload :: Maybe [Element]
                            , messageErrorStanzaError :: StanzaError }
               deriving (Eq, Show)


-- |
-- @MessageType@ holds XMPP message types as defined in XMPP-IM. @Normal@ is the
-- default message type.

data MessageType = Chat |
                   Error |
                   Groupchat |
                   Headline |
                   Normal |
                   OtherMessageType String deriving (Eq, Show)


-- |
-- The presence stanza - either a presence or a presence error.

data Presence = Presence { presenceID :: Maybe StanzaID
                         , presenceFrom :: Maybe From
                         , presenceTo :: Maybe To
                         , presenceXMLLang  :: Maybe XMLLang
                         , presenceType :: PresenceType
                         , presencePayload :: [Element] } |
                PresenceError { presenceID :: Maybe StanzaID
                              , presenceFrom :: Maybe From
                              , presenceTo :: Maybe To
                              , presenceXMLLang  :: Maybe XMLLang
                              , presenceErrorPayload :: Maybe [Element]
                              , presenceErrorStanzaError :: StanzaError }
                deriving (Eq, Show)


-- |
-- @PresenceType@ holds XMPP presence types. When a presence type is not
-- provided, we assign the @PresenceType@ value @Available@.

data PresenceType = Subscribe    | -- ^ Sender wants to subscribe to presence
                    Subscribed   | -- ^ Sender has approved the subscription
                    Unsubscribe  | -- ^ Sender is unsubscribing from presence
                    Unsubscribed | -- ^ Sender has denied or cancelled a
                                   --   subscription
                    Probe        | -- ^ Sender requests current presence;
                                   --   should only be used by servers
                    Available    | -- ^ Sender did not specify a type attribute
                    Unavailable deriving (Eq, Show)


-- |
-- All stanzas (IQ, message, presence) can cause errors, which in the XMPP
-- stream looks like <stanza-kind to='sender' type='error'>. These errors are
-- wrapped in the @StanzaError@ type.

data StanzaError = StanzaError { stanzaErrorType :: StanzaErrorType
                               , stanzaErrorCondition :: StanzaErrorCondition
                               , stanzaErrorText :: Maybe String
                               , stanzaErrorApplicationSpecificCondition ::
                                 Maybe Element } deriving (Eq, Show)


-- |
-- @StanzaError@s always have one of these types.

data StanzaErrorType = Cancel   | -- ^ Error is unrecoverable - do not retry
                       Continue | -- ^ Conditition was a warning - proceed
                       Modify   | -- ^ Change the data and retry
                       Auth     | -- ^ Provide credentials and retry
                       Wait       -- ^ Error is temporary - wait and retry
                       deriving (Eq, Show)


-- |
-- Stanza errors are accommodated with one of the error conditions listed below.

data StanzaErrorCondition = BadRequest            | -- ^ Malformed XML
                            Conflict              | -- ^ Resource or session
                                                    --   with name already
                                                    --   exists
                            FeatureNotImplemented |
                            Forbidden             | -- ^ Insufficient
                                                    --   permissions
                            Gone                  | -- ^ Entity can no longer
                                                    --   be contacted at this
                                                    --   address
                            InternalServerError   |
                            ItemNotFound          |
                            JIDMalformed          |
                            NotAcceptable         | -- ^ Does not meet policy
                                                    --   criteria
                            NotAllowed            | -- ^ No entity may perform
                                                    --   this action
                            NotAuthorized         | -- ^ Must provide proper
                                                    --   credentials
                            PaymentRequired       |
                            RecipientUnavailable  | -- ^ Temporarily
                                                    --   unavailable
                            Redirect              | -- ^ Redirecting to other
                                                    --   entity, usually
                                                    --   temporarily
                            RegistrationRequired  |
                            RemoteServerNotFound  |
                            RemoteServerTimeout   |
                            ResourceConstraint    | -- ^ Entity lacks the
                                                    --   necessary system
                                                    --   resources
                            ServiceUnavailable    |
                            SubscriptionRequired  |
                            UndefinedCondition    | -- ^ Application-specific
                                                    --   condition
                            UnexpectedRequest       -- ^ Badly timed request
                            deriving (Eq, Show)



-- =============================================================================
--  OTHER STUFF
-- =============================================================================


data SASLFailure = SASLFailure { saslFailureCondition :: SASLError
                               , saslFailureText :: Maybe String } -- TODO: XMLLang


data SASLError = -- SASLAborted | -- Client aborted - should not happen
                 SASLAccountDisabled | -- ^ The account has been temporarily
                                       --   disabled
                 SASLCredentialsExpired | -- ^ The authentication failed because
                                          --   the credentials have expired
                 SASLEncryptionRequired | -- ^ The mechanism requested cannot be
                                          --   used the confidentiality and
                                          --   integrity of the underlying
                                          --   stream is protected (typically
                                          --   with TLS)
                 -- SASLIncorrectEncoding | -- The base64 encoding is incorrect
                                            -- - should not happen
                 -- SASLInvalidAuthzid | -- The authzid has an incorrect format,
                                         -- or the initiating entity does not
                                         -- have the appropriate permissions to
                                         -- authorize that ID
                 SASLInvalidMechanism | -- ^ The mechanism is not supported by
                                        --   the receiving entity
                 -- SASLMalformedRequest | -- Invalid syntax - should not happen
                 SASLMechanismTooWeak | -- ^ The receiving entity policy
                                        --   requires a stronger mechanism
                 SASLNotAuthorized (Maybe String) | -- ^ Invalid credentials
                                                    --   provided, or some
                                                    --   generic authentication
                                                    --   failure has occurred
                 SASLTemporaryAuthFailure -- ^ There receiving entity reported a
                                          --   temporary error condition; the
                                          --   initiating entity is recommended
                                          --   to try again later


instance Eq ConnectionState where
  Disconnected == Disconnected = True
  (Connected p h) == (Connected p_ h_) = p == p_ && h == h_
  -- (ConnectedPostFeatures s p h t) == (ConnectedPostFeatures s p h t) = True
  -- (ConnectedAuthenticated s p h t) == (ConnectedAuthenticated s p h t) = True
  _ == _ = False

data XMPPError = UncaughtEvent deriving (Eq, Show)

instance CME.Error XMPPError where
  strMsg "UncaughtEvent" = UncaughtEvent


-- | Readability type for host name Strings.

type HostName = String -- This is defined in Network as well


-- | Readability type for port number Integers.

type PortNumber = Integer -- We use N(etwork).PortID (PortNumber) internally


-- | Readability type for user name Strings.

type UserName = String


-- | Readability type for password Strings.

type Password = String


-- | Readability type for (Address) resource identifier Strings.

type Resource = String


-- An XMLEvent is triggered by an XML stanza or some other XML event, and is
-- sent through the internal event channel, just like client action events.

data XMLEvent = XEBeginStream String | XEFeatures String |
                XEChallenge Challenge | XESuccess Success |
                XEEndStream | XEIQ IQ | XEPresence Presence |
                XEMessage Message | XEProceed |
                XEOther String deriving (Show)

data EnumeratorEvent = EnumeratorDone |
                       EnumeratorXML XMLEvent |
                       EnumeratorException CE.SomeException
                       deriving (Show)


-- Type to contain the internal events.

data InternalEvent s m = IEC (ClientEvent s m) | IEE EnumeratorEvent | IET (TimeoutEvent s m) deriving (Show)

data TimeoutEvent s m = TimeoutEvent StanzaID Timeout (StateT s m ())

instance Show (TimeoutEvent s m) where
    show (TimeoutEvent (SID i) t _) = "TimeoutEvent (ID: " ++ (show i) ++ ", timeout: " ++ (show t) ++ ")"


data StreamState = PreStream |
                   PreFeatures StreamProperties |
                   PostFeatures StreamProperties StreamFeatures


data AuthenticationState = NoAuthentication | AuthenticatingPreChallenge1 String String (Maybe Resource) | AuthenticatingPreChallenge2 String String (Maybe Resource) | AuthenticatingPreSuccess String String (Maybe Resource) | AuthenticatedUnbound String (Maybe Resource) | AuthenticatedBound String Resource


-- Client actions that needs to be performed in the (main) state loop are
-- converted to ClientEvents and sent through the internal event channel.

data ClientEvent s m = CEOpenStream N.HostName PortNumber
                       (OpenStreamResult -> StateT s m ()) |
                       CESecureWithTLS (Maybe ([X509], Bool)) ([X509] -> Bool) (Maybe [String])
                       (SecureWithTLSResult -> StateT s m ()) |
                       CEAuthenticate UserName Password (Maybe Resource)
                       (AuthenticateResult -> StateT s m ()) |
                       CEMessage Message (Maybe (Message -> StateT s m Bool)) (Maybe (Timeout, StateT s m ())) (Maybe (StreamError -> StateT s m ())) |
                       CEPresence Presence (Maybe (Presence -> StateT s m Bool)) (Maybe (Timeout, StateT s m ())) (Maybe (StreamError -> StateT s m ())) |
                       CEIQ IQ (Maybe (IQ -> StateT s m Bool)) (Maybe (Timeout, StateT s m ())) (Maybe (StreamError -> StateT s m ())) |
                       CEAction (Maybe (StateT s m Bool)) (StateT s m ())

instance Show (ClientEvent s m) where
  show (CEOpenStream h p _) = "CEOpenStream " ++ h ++ " " ++ (show p)
  show (CESecureWithTLS c _ _ _) = "CESecureWithTLS " ++ (show c)
  show (CEAuthenticate u p r _) = "CEAuthenticate " ++ u ++ " " ++ p ++ " " ++
                                    (show r)
  show (CEIQ s _ _ _) = "CEIQ"
  show (CEMessage s _ _ _) = "CEMessage"
  show (CEPresence s _ _ _) = "CEPresence"

  show (CEAction _ _) = "CEAction"


type StreamID = String

data ConnectionState = Disconnected | Connected ServerAddress Handle

data TLSState = NoTLS | PreProceed | PreHandshake | PostHandshake TLSCtx

data Challenge = Chal String deriving (Show)

data Success = Succ String deriving (Show)


type StreamProperties = Float
type StreamFeatures = String


data ConnectResult = ConnectSuccess StreamProperties StreamFeatures (Maybe Resource) |
                     ConnectOpenStreamFailure |
                     ConnectSecureWithTLSFailure |
                     ConnectAuthenticateFailure

data OpenStreamResult = OpenStreamSuccess StreamProperties StreamFeatures |
                        OpenStreamFailure

data SecureWithTLSResult = SecureWithTLSSuccess StreamProperties StreamFeatures | SecureWithTLSFailure

data AuthenticateResult = AuthenticateSuccess StreamProperties StreamFeatures Resource | AuthenticateFailure

-- Address is a data type that has to be constructed in this module using either
-- address or stringToAddress.

data Address = Address { localpart :: Maybe Localpart
                       , domainpart :: Domainpart
                       , resourcepart :: Maybe Resourcepart }
                       deriving (Eq)

instance Show Address where
    show (Address { localpart = n, domainpart = s, resourcepart = r })
        | n == Nothing && r == Nothing = s
        | r == Nothing                 = let Just n' = n in n' ++ "@" ++ s
        | n == Nothing                 = let Just r' = r in s ++ "/" ++ r'
        | otherwise                    = let Just n' = n; Just r' = r
                                         in n' ++ "@" ++ s ++ "/" ++ r'

type Localpart = String
type Domainpart = String
type Resourcepart = String

data ServerAddress = ServerAddress N.HostName N.PortNumber deriving (Eq)

type Timeout = Int

data StreamError = StreamError


-- =============================================================================
--  XML TYPES
-- =============================================================================

type XMLLang = String
-- Validate, protect. See:
-- http://tools.ietf.org/html/rfc6120#section-8.1.5
-- http://www.w3.org/TR/2008/REC-xml-20081126/
-- http://www.rfc-editor.org/rfc/bcp/bcp47.txt
-- http://www.ietf.org/rfc/rfc1766.txt


newtype IDGenerator = IDGenerator (IORef [String])
