{-# LANGUAGE RankNTypes #-}
module State.ListOverlay
  ( listOverlayActivateCurrent
  , listOverlaySearchString
  , listOverlayMove
  , exitListOverlay
  , enterListOverlayMode
  , resetListOverlaySearch
  , onEventListOverlay
  )
where

import           Prelude ()
import           Prelude.MH

import qualified Brick.Widgets.List as L
import qualified Brick.Widgets.Edit as E
import qualified Data.Text.Zipper as Z
import qualified Data.Vector as Vec
import           Lens.Micro.Platform ( Lens', (%=), (.=) )
import           Network.Mattermost.Types ( Session )
import qualified Graphics.Vty as Vty

import           Types
import           State.Common
import           Events.Keybindings ( KeyConfig, Keybinding, handleKeyboardEvent )


-- | Activate the specified list overlay's selected item by invoking the
-- overlay's configured enter keypress handler function.
listOverlayActivateCurrent :: Lens' ChatState (ListOverlayState a b) -> MH ()
listOverlayActivateCurrent which = do
  mItem <- L.listSelectedElement <$> use (which.listOverlaySearchResults)
  case mItem of
      Nothing -> return ()
      Just (_, val) -> do
          handler <- use (which.listOverlayEnterHandler)
          activated <- handler val
          if activated
             then setMode Main
             else return ()

-- | Get the current search string for the specified overlay.
listOverlaySearchString :: Lens' ChatState (ListOverlayState a b) -> MH Text
listOverlaySearchString which =
    (head . E.getEditContents) <$> use (which.listOverlaySearchInput)

-- | Move the list cursor in the specified overlay.
listOverlayMove :: Lens' ChatState (ListOverlayState a b)
                -- ^ Which overlay
                -> (L.List Name a -> L.List Name a)
                -- ^ How to transform the list in the overlay
                -> MH ()
listOverlayMove which how = which.listOverlaySearchResults %= how

-- | Clear the state of the specified list overlay and return to the
-- Main mode.
exitListOverlay :: Lens' ChatState (ListOverlayState a b)
                -- ^ Which overlay to reset
                -> MH ()
exitListOverlay which = do
    newList <- use (which.listOverlayNewList)
    which.listOverlaySearchResults .= newList mempty
    which.listOverlayEnterHandler .= (const $ return False)
    setMode Main

-- | Initialize a list overlay with the specified arguments and switch
-- to the specified mode.
enterListOverlayMode :: (Lens' ChatState (ListOverlayState a b))
                     -- ^ Which overlay to initialize
                     -> Mode
                     -- ^ The mode to change to
                     -> b
                     -- ^ The overlay's initial search scope
                     -> (a -> MH Bool)
                     -- ^ The overlay's enter keypress handler
                     -> (ChatState -> b -> Session -> Text -> IO (Vec.Vector a))
                     -- ^ The overlay's results fetcher function
                     -> MH ()
enterListOverlayMode which mode scope enterHandler fetcher = do
    which.listOverlaySearchScope .= scope
    which.listOverlaySearchInput.E.editContentsL %= Z.clearZipper
    which.listOverlayEnterHandler .= enterHandler
    which.listOverlayFetchResults .= fetcher
    which.listOverlaySearching .= False
    newList <- use (which.listOverlayNewList)
    which.listOverlaySearchResults .= newList mempty
    setMode mode
    resetListOverlaySearch which

-- | Reset the overlay's search by initiating a new search request for
-- the string that is currently in the overlay's editor. This does
-- nothing if a search for this overlay is already in progress.
resetListOverlaySearch :: Lens' ChatState (ListOverlayState a b) -> MH ()
resetListOverlaySearch which = do
    searchPending <- use (which.listOverlaySearching)

    when (not searchPending) $ do
        searchString <- listOverlaySearchString which
        which.listOverlaySearching .= True
        newList <- use (which.listOverlayNewList)
        session <- getSession
        scope <- use (which.listOverlaySearchScope)
        fetcher <- use (which.listOverlayFetchResults)
        st <- use id
        doAsyncWith Preempt $ do
            results <- fetcher st scope session searchString
            return $ Just $ do
                which.listOverlaySearchResults .= newList results
                which.listOverlaySearching .= False

                -- Now that the results are available, check to see if the
                -- search string changed since this request was submitted.
                -- If so, issue another search.
                afterSearchString <- listOverlaySearchString which
                when (searchString /= afterSearchString) $ resetListOverlaySearch which

-- | Generically handle an event for the list overlay state targeted
-- by the specified lens. Automatically dispatches new searches in the
-- overlay's editor if the editor contents change.
onEventListOverlay :: Lens' ChatState (ListOverlayState a b)
                   -- ^ Which overlay to dispatch to?
                   -> (KeyConfig -> [Keybinding])
                   -- ^ The keybinding builder
                   -> Vty.Event
                   -- ^ The event
                   -> MH ()
onEventListOverlay which keybindings =
    handleKeyboardEvent keybindings $ \e -> do
        -- Get the editor content before the event.
        before <- listOverlaySearchString which

        -- Handle the editor input event.
        mhHandleEventLensed (which.listOverlaySearchInput) E.handleEditorEvent e

        -- Get the editor content after the event. If the string changed,
        -- start a new search.
        after <- listOverlaySearchString which
        when (before /= after) $ resetListOverlaySearch which
