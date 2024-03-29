import System.Environment (getArgs)

import Data.Char (isDigit)
import Data.List (stripPrefix)

import Data.Text.Lazy (Text)
import Text.Read (readMaybe)
import qualified Data.Text.Lazy as T
import qualified Data.Text.Lazy.Encoding as E

import Web.Scotty
import Network.Wai.Middleware.Cors
import Network.HTTP.Types.Status (status200, status400)


-- S-expression data type
data SExpr = SInt Int
           | SFloat Double
           | SString String
           | SSym String
           | SList [SExpr]
           deriving (Show)


main :: IO ()
main = do
    args <- getArgs
    let port = case args of
                 (x:_) -> maybe 3210 id (readMaybe x :: Maybe Int)
                 []    -> 3210
    scotty port $ do -- Starts server
        middleware simpleCors -- Enables CORS
        post(capture "/convert") $ do -- Handles POST requests to /convert
            sexpr <- body
            case parseSExpr . T.unpack . E.decodeUtf8 $ sexpr of
                Just json -> do -- If parsing is successful
                    status status200
                    text (T.pack (convertToJSON json))  -- Sends JSON response
                Nothing -> do -- If parsing fails
                    status status400
                    text (T.pack "\"Invalid input\"")


-- Main parsing function
parseSExpr :: String -> Maybe SExpr
parseSExpr str = parse (trimSpaces str) -- Removes spaces at the beginning and the end before parsing
    where
        parse :: String -> Maybe SExpr
        parse "" = Nothing
        parse ('(':xs) = if last xs == ')' then fmap SList (parseList (init xs)) else Nothing -- Parses lists
        parse ('"':xs) = fmap SString (parseString xs) -- Parses strings 
        parse str | all isDigitOrMinus str = Just (SInt (read str)) -- Checks if it is an integer
                  | isFloat str = Just (SFloat (read str)) -- Checks if it is a float
                  | all isSymbol str = Just (SSym str) -- Checks if it is a symbol
                  | otherwise = Nothing -- Fails parsing


trimSpaces :: String -> String
trimSpaces = dropWhile (== ' ') . reverse . dropWhile (== ' ') . reverse


-- Parses strings outsite of lists
parseString :: String -> Maybe String
parseString "" = Nothing
parseString ('\\':x:xs) = case x of -- Untested code
    'n' -> fmap ('\n':) (parseString xs)
    '"' -> fmap ('"':) (parseString xs)
    '\\' -> fmap ('\\':) (parseString xs)
    _ -> fmap (x:) (parseString xs)
parseString ('"':xs) = if length xs == 0 then Just "" else Nothing -- Handle cases like a", "a, "a"", "a"b"
parseString (x:xs) = fmap (x:) (parseString xs)

-- Parses lists outsite of lists
parseList :: String -> Maybe [SExpr]
parseList input = parseListAux input >>= mapM parseSExpr
    where
        parseListAux :: String -> Maybe [String]
        parseListAux "" = Just []
        parseListAux (' ':xs) = parseListAux xs -- Ignores spaces in lists
        parseListAux ('(':xs) = do  -- Parses nested lists
            token <- parseParenthesis xs -- Gets the nested list
            rest <- stripPrefix token xs -- Gets the rest of the string
            tokens <- parseListAux rest -- Parses the rest of the string
            return $ ("(" ++ token) : tokens -- Concatenates the two parts
        parseListAux ('"':xs) = do -- Parses strings in lists
            token <- parseQuotes xs
            rest <- stripPrefix token xs
            tokens <- parseListAux rest
            return $ ("\"" ++ token) : tokens
        parseListAux s = do -- Parses tokens in lists
            token <- parseToken s
            rest <- stripPrefix token s
            tokens <- parseListAux rest
            return $ token : tokens


-- Parses strings inside of lists
parseQuotes :: String -> Maybe String
parseQuotes "" = Nothing
parseQuotes ('\\':x:xs) = case x of -- Untested code
    'n' -> fmap ('\n':) (parseQuotes xs)
    '"' -> fmap ('"':) (parseQuotes xs)
    '\\' -> fmap ('\\':) (parseQuotes xs)
    _ -> fmap (x:) (parseQuotes xs)
parseQuotes ('"':xs) = Just "\""
parseQuotes (x:xs) = fmap (x:) (parseQuotes xs)

-- Parses lists inside of lists
parseParenthesis :: String -> Maybe String
parseParenthesis x = parse x 0
    where -- An aux function is used to count the number of parenthesis
        parse :: String -> Int -> Maybe String
        parse "" _ = Nothing
        parse (')':xs) n = if n == 0 then Just ")" else fmap (')':) (parse xs (n-1))
        parse ('(':xs) n = fmap ('(':) (parse xs (n+1))
        parse (x:xs) n = fmap (x:) (parse xs n)

-- Parses everything that is neither a list or a string inside of lists
parseToken :: String -> Maybe String
parseToken "" = Just ""
parseToken (' ':xs) = Just ""
parseToken (')':xs) = Nothing -- Handles cases like ()), (a)), (a)b)
parseToken (x:xs) = fmap (x:) (parseToken xs)


isDigitOrMinus :: Char -> Bool
isDigitOrMinus '-' = True
isDigitOrMinus c = isDigit c

isFloat :: String -> Bool
isFloat str = case readMaybe str :: Maybe Double of
    Just _ -> True
    Nothing -> False

isSymbol :: Char -> Bool
isSymbol c = c `notElem` ['(', ')', '"', '\\', ' ']


convertToJSON :: SExpr -> String
convertToJSON (SSym "true") = "true"
convertToJSON (SSym "false") = "false"
convertToJSON (SSym "null") = "null"
convertToJSON (SInt i) = show i
convertToJSON (SFloat f) = show f
convertToJSON (SString s) = "\"" ++ s ++ "\""
convertToJSON (SSym sym) = "{\"symbol\": \"" ++ sym ++ "\"}"
convertToJSON (SList items) = "[" ++ (convertListItems items) ++ "]"
    where
        convertListItems :: [SExpr] -> String -- Parses S-Expressions lists to Json (as a string)
        convertListItems [] = ""
        convertListItems [x] = convertToJSON x
        convertListItems (x:xs) = (convertToJSON x) ++ ", " ++ (convertListItems xs)
