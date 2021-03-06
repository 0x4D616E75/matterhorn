{-# LANGUAGE MultiWayIf #-}
module Matterhorn.Events.Main where

import           Prelude ()
import           Matterhorn.Prelude

import           Brick.Widgets.Edit
import qualified Graphics.Vty as Vty

import           Matterhorn.Command
import           Matterhorn.Events.Keybindings
import           Matterhorn.State.Attachments
import           Matterhorn.State.ChannelSelect
import           Matterhorn.State.ChannelList
import           Matterhorn.State.Channels
import           Matterhorn.State.Editing
import           Matterhorn.State.MessageSelect
import           Matterhorn.State.PostListOverlay ( enterFlaggedPostListMode )
import           Matterhorn.State.Teams
import           Matterhorn.State.UrlSelect
import           Matterhorn.Types


onEventMain :: Vty.Event -> MH ()
onEventMain =
  void . handleKeyboardEvent mainKeybindings (\ ev -> do
      resetReturnChannel
      case ev of
          (Vty.EvPaste bytes) -> handlePaste bytes
          _ -> handleEditingInput ev
  )

mainKeybindings :: KeyConfig -> KeyHandlerMap
mainKeybindings = mkKeybindings mainKeyHandlers

mainKeyHandlers :: [KeyEventHandler]
mainKeyHandlers =
    [ mkKb EnterSelectModeEvent
        "Select a message to edit/reply/delete"
        beginMessageSelect

    , mkKb ReplyRecentEvent
        "Reply to the most recent message"
        replyToLatestMessage

    , mkKb ToggleMessagePreviewEvent "Toggle message preview"
        toggleMessagePreview

    , mkKb ToggleChannelListVisibleEvent "Toggle channel list visibility"
        toggleChannelListVisibility

    , mkKb ToggleExpandedChannelTopicsEvent "Toggle display of expanded channel topics"
        toggleExpandedChannelTopics

    , mkKb NextTeamEvent "Switch to the next available team"
        nextTeam

    , mkKb PrevTeamEvent "Switch to the previous available team"
        prevTeam

    , mkKb MoveCurrentTeamLeftEvent "Move the current team to the left in the team list"
        moveCurrentTeamLeft

    , mkKb MoveCurrentTeamRightEvent "Move the current team to the right in the team list"
        moveCurrentTeamRight

    , mkKb
        InvokeEditorEvent
        "Invoke `$EDITOR` to edit the current message"
        invokeExternalEditor

    , mkKb
        EnterFastSelectModeEvent
        "Enter fast channel selection mode"
         beginChannelSelect

    , mkKb
        QuitEvent
        "Quit"
        requestQuit

    , staticKb "Tab-complete forward"
         (Vty.EvKey (Vty.KChar '\t') []) $
         tabComplete Forwards

    , staticKb "Tab-complete backward"
         (Vty.EvKey (Vty.KBackTab) []) $
         tabComplete Backwards

    , mkKb
        ScrollUpEvent
        "Scroll up in the channel input history" $ do
             -- Up in multiline mode does the usual thing; otherwise we
             -- navigate the history.
             isMultiline <- use (csCurrentTeam.tsEditState.cedEphemeral.eesMultiline)
             case isMultiline of
                 True -> mhHandleEventLensed (csCurrentTeam.tsEditState.cedEditor) handleEditorEvent
                                           (Vty.EvKey Vty.KUp [])
                 False -> channelHistoryBackward

    , mkKb
        ScrollDownEvent
        "Scroll down in the channel input history" $ do
             -- Down in multiline mode does the usual thing; otherwise
             -- we navigate the history.
             isMultiline <- use (csCurrentTeam.tsEditState.cedEphemeral.eesMultiline)
             case isMultiline of
                 True -> mhHandleEventLensed (csCurrentTeam.tsEditState.cedEditor) handleEditorEvent
                                           (Vty.EvKey Vty.KDown [])
                 False -> channelHistoryForward

    , mkKb PageUpEvent "Page up in the channel message list (enters message select mode)" $ do
             beginMessageSelect

    , mkKb SelectOldestMessageEvent "Scroll to top of channel message list" $ do
             beginMessageSelect
             messageSelectFirst

    , mkKb NextChannelEvent "Change to the next channel in the channel list"
         nextChannel

    , mkKb PrevChannelEvent "Change to the previous channel in the channel list"
         prevChannel

    , mkKb NextUnreadChannelEvent "Change to the next channel with unread messages or return to the channel marked '~'"
         nextUnreadChannel

    , mkKb ShowAttachmentListEvent "Show the attachment list"
         showAttachmentList

    , mkKb NextUnreadUserOrChannelEvent
         "Change to the next channel with unread messages preferring direct messages"
         nextUnreadUserOrChannel

    , mkKb LastChannelEvent "Change to the most recently-focused channel"
         recentChannel

    , staticKb "Send the current message"
         (Vty.EvKey Vty.KEnter []) $ do
             isMultiline <- use (csCurrentTeam.tsEditState.cedEphemeral.eesMultiline)
             case isMultiline of
                 -- Normally, this event causes the current message to
                 -- be sent. But in multiline mode we want to insert a
                 -- newline instead.
                 True -> handleEditingInput (Vty.EvKey Vty.KEnter [])
                 False -> do
                     tId <- use csCurrentTeamId
                     cId <- use (csCurrentChannelId tId)
                     content <- getEditorContent
                     handleInputSubmission tId cId content

    , mkKb EnterOpenURLModeEvent "Select and open a URL posted to the current channel"
           startUrlSelect

    , mkKb ClearUnreadEvent "Clear the current channel's unread / edited indicators" $ do
           tId <- use csCurrentTeamId
           clearChannelUnreadStatus =<< use (csCurrentChannelId tId)

    , mkKb ToggleMultiLineEvent "Toggle multi-line message compose mode"
           toggleMultilineEditing

    , mkKb CancelEvent "Cancel autocomplete, message reply, or edit, in that order"
         cancelAutocompleteOrReplyOrEdit

    , mkKb EnterFlaggedPostsEvent "View currently flagged posts"
         enterFlaggedPostListMode
    ]
