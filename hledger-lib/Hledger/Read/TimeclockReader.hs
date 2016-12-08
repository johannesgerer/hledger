{-|

A reader for the timeclock file format generated by timeclock.el
(<http://www.emacswiki.org/emacs/TimeClock>). Example:

@
i 2007\/03\/10 12:26:00 hledger
o 2007\/03\/10 17:26:02
@

From timeclock.el 2.6:

@
A timeclock contains data in the form of a single entry per line.
Each entry has the form:

  CODE YYYY/MM/DD HH:MM:SS [COMMENT]

CODE is one of: b, h, i, o or O.  COMMENT is optional when the code is
i, o or O.  The meanings of the codes are:

  b  Set the current time balance, or \"time debt\".  Useful when
     archiving old log data, when a debt must be carried forward.
     The COMMENT here is the number of seconds of debt.

  h  Set the required working time for the given day.  This must
     be the first entry for that day.  The COMMENT in this case is
     the number of hours in this workday.  Floating point amounts
     are allowed.

  i  Clock in.  The COMMENT in this case should be the name of the
     project worked on.

  o  Clock out.  COMMENT is unnecessary, but can be used to provide
     a description of how the period went, for example.

  O  Final clock out.  Whatever project was being worked on, it is
     now finished.  Useful for creating summary reports.
@

-}

{-# LANGUAGE OverloadedStrings #-}

module Hledger.Read.TimeclockReader (
  -- * Reader
  reader,
  -- * Misc other exports
  timeclockfilep,
  -- * Tests
  tests_Hledger_Read_TimeclockReader
)
where
import           Prelude ()
import           Prelude.Compat
import           Control.Monad
import           Control.Monad.Except (ExceptT)
import           Control.Monad.State.Strict
import           Data.Maybe (fromMaybe)
import           Data.Text (Text)
import qualified Data.Text as T
import           Test.HUnit
import           Text.Megaparsec hiding (parse)

import           Hledger.Data
-- XXX too much reuse ?
import           Hledger.Read.Common
import           Hledger.Utils


reader :: Reader
reader = Reader
  {rFormat     = "timeclock"
  ,rExtensions = ["timeclock"]
  ,rParser     = parse
  ,rExperimental = False
  }

-- | Parse and post-process a "Journal" from timeclock.el's timeclock
-- format, saving the provided file path and the current time, or give an
-- error.
parse :: Maybe FilePath -> Bool -> FilePath -> Text -> ExceptT String IO Journal
parse _ = parseAndFinaliseJournal timeclockfilep

timeclockfilep :: ErroringJournalParser IO ParsedJournal
timeclockfilep = do many timeclockitemp
                    eof
                    j@Journal{jparsetimeclockentries=es} <- get
                    -- Convert timeclock entries in this journal to transactions, closing any unfinished sessions.
                    -- Doing this here rather than in journalFinalise means timeclock sessions can't span file boundaries,
                    -- but it simplifies code above.
                    now <- liftIO getCurrentLocalTime
                    -- entries have been parsed in reverse order. timeclockEntriesToTransactions
                    -- expects them to be in normal order, then we must reverse again since
                    -- journalFinalise expects them in reverse order
                    let j' = j{jtxns = reverse $ timeclockEntriesToTransactions now $ reverse es, jparsetimeclockentries = []}
                    return j'
    where
      -- As all ledger line types can be distinguished by the first
      -- character, excepting transactions versus empty (blank or
      -- comment-only) lines, can use choice w/o try
      timeclockitemp = choice [ 
                            void emptyorcommentlinep
                          , timeclockentryp >>= \e -> modify' (\j -> j{jparsetimeclockentries = e : jparsetimeclockentries j})
                          ] <?> "timeclock entry, or default year or historical price directive"

-- | Parse a timeclock entry.
timeclockentryp :: JournalStateParser m TimeclockEntry
timeclockentryp = do
  sourcepos <- genericSourcePos <$> lift getPosition
  code <- oneOf ("bhioO" :: [Char])
  lift (some spacenonewline)
  datetime <- datetimep
  account <- fromMaybe "" <$> optional (lift (some spacenonewline) >> modifiedaccountnamep)
  description <- T.pack . fromMaybe "" <$> lift (optional (some spacenonewline >> restofline))
  return $ TimeclockEntry sourcepos (read [code]) datetime account description

tests_Hledger_Read_TimeclockReader = TestList [
 ]

