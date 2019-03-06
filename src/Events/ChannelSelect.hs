module Events.ChannelSelect where

import           Prelude ()
import           Prelude.MH

import           Brick.Widgets.Edit ( handleEditorEvent )
import qualified Graphics.Vty as Vty

import           Events.Keybindings
import           State.Channels
import           State.ChannelSelect
import           Types
import qualified Zipper as Z


onEventChannelSelect :: Vty.Event -> MH ()
onEventChannelSelect =
  handleKeyboardEvent channelSelectKeybindings $ \e -> do
      mhHandleEventLensed (csChannelSelectState.channelSelectInput) handleEditorEvent e
      updateChannelSelectMatches

channelSelectKeybindings :: KeyConfig -> [Keybinding]
channelSelectKeybindings = mkKeybindings
    [ staticKb "Switch to selected channel"
         (Vty.EvKey Vty.KEnter []) $ do
             matches <- use (csChannelSelectState.channelSelectMatches)
             case Z.focus matches of
                 Nothing -> return ()
                 Just match -> do
                     setMode Main
                     setFocus $ channelListEntryChannelHandle $ matchEntry match

    , mkKb CancelEvent "Cancel channel selection" $ setMode Main
    , mkKb NextChannelEvent "Select next match" channelSelectNext
    , mkKb PrevChannelEvent "Select previous match" channelSelectPrevious
    ]
