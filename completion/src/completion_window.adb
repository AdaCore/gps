-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                        Copyright (C) 2006                         --
--                              AdaCore                              --
--                                                                   --
-- GPS is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this library; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Glib.Values;            use Glib.Values;
with Glib.Convert;           use Glib.Convert;

with Gdk.Event;              use Gdk.Event;
with Gdk.Rectangle;          use Gdk.Rectangle;
with Gdk.Window;             use Gdk.Window;
with Gdk.Types;              use Gdk.Types;
with Gdk.Types.Keysyms;      use Gdk.Types.Keysyms;

with Gtk.Box;                use Gtk.Box;
with Gtk.Handlers;           use Gtk.Handlers;
with Gtk.Frame;              use Gtk.Frame;
with Gtk.Enums;              use Gtk.Enums;
with Gtk.Tree_Selection;     use Gtk.Tree_Selection;
with Gtk.Tree_View_Column;   use Gtk.Tree_View_Column;
with Gtk.Cell_Renderer_Text; use Gtk.Cell_Renderer_Text;
with Gtk.Style;              use Gtk.Style;
with Gtk.Scrollbar;          use Gtk.Scrollbar;
with Gtk.Widget;             use Gtk.Widget;

with Gtk.Viewport;           use Gtk.Viewport;

with Pango.Font;             use Pango.Font;
with Pango.Layout;           use Pango.Layout;

with Ada.Characters.Handling;   use Ada.Characters.Handling;
with Ada.Exceptions;            use Ada.Exceptions;
with Ada.Unchecked_Deallocation;

with Basic_Types;               use Basic_Types;
with Traces;                    use Traces;
with GPS.Kernel.Standard_Hooks; use GPS.Kernel.Standard_Hooks;
with VFS;                       use VFS;

package body Completion_Window is

   Markup_Column : constant := 0;
   Index_Column  : constant := 1;

   Minimal_Items_To_Show : constant := 50;

   Max_Window_Width : constant := 300;
   --  Maximum width of the window, in pixels.

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (String, String_Access);

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (Information_Array, Information_Array_Access);

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (Completion_Proposal'Class, Completion_Proposal_Access);

   package Return_Cb is new Gtk.Handlers.Return_Callback
     (Completion_Window_Record, Boolean);
   use Return_Cb;

   package Cb is new Gtk.Handlers.Callback (Completion_Window_Record);
   use Cb;

   Column_Types : constant GType_Array :=
     (Markup_Column => GType_String,
      Index_Column  => GType_Int);

   function On_Focus_Out
     (Window : access Completion_Window_Record'Class;
      Event  : Gdk_Event) return Boolean;
   --  Callback for a focus_out_event on the tree view.

   function On_Key_Press
     (Window : access Completion_Window_Record'Class;
      Event  : Gdk_Event) return Boolean;
   --  Callback for a key_press_event on the text view

   procedure Insert_Text_Handler
     (Window : access Completion_Window_Record'Class;
      Params : Glib.Values.GValues);
   --  Callback after a text insertion.

   procedure Mark_Set_Handler
     (Window : access Completion_Window_Record'Class;
      Params : Glib.Values.GValues);
   --  Callback after a Mark set on the buffer.

   procedure Delete_Text_Handler
     (Window : access Completion_Window_Record'Class;
      Params : Glib.Values.GValues);
   --  Callback after a text deletion.

   procedure Before_Delete_Text_Handler
     (Window : access Completion_Window_Record'Class;
      Params : Glib.Values.GValues);
   --  Callback before a text deletion.

   function On_Button_Pressed
     (Window : access Completion_Window_Record'Class;
      Event  : Gdk_Event) return Boolean;
   --  Callback on a button press in the tree view.

   procedure On_Selection_Changed
     (Window : access Completion_Window_Record'Class);
   --  Callback on a selection change in the tree view.

   procedure On_Location_Button_Clicked
     (Window : access Completion_Window_Record'Class);
   --  Callback on a click on the location button

   procedure Adjust_Selected
     (Window : access Completion_Window_Record'Class;
      UTF8   : String);
   --  Show only the items that begin with UTF8. Delete the window if there is
   --  none.

   procedure Expand_Selection
     (Window      : access Completion_Window_Record'Class;
      UTF8_Filter : String;
      Number      : Natural);
   --  Expand the current selection until Number entries have been added or
   --  the completion iter has reach the end.

   procedure Free (X : in out Information_Record);
   --  Free memory associated to X.

   procedure Complete_And_Exit
     (Window : access Completion_Window_Record'Class);
   --  Complete using the current selection and exit.

   function Complete_Common_Prefix
     (Window : access Completion_Window_Record'Class) return Boolean;
   --  Complete the text up to the biggest common prefix in the list.
   --  Return True if completion actually occurred.

   function To_Showable_String
     (P : Completion_Proposal'Class) return String;
   --  Return the string to display in the main window.

   function To_Showable_String
     (P : Completion_Proposal'Class) return String is
   begin
      return Escape_Text (Get_Label (P));
   end To_Showable_String;

   ----------
   -- Free --
   ----------

   procedure Free (X : in out Information_Record) is
   begin
      Unchecked_Free (X.Markup);
      Unchecked_Free (X.Text);

      if X.Notes /= null then
         Unchecked_Free (X.Notes);
      end if;

      Unchecked_Free (X.Proposal);
      --  ??? Should we free X.Proposal ?
   end Free;

   ------------
   -- Delete --
   ------------

   procedure Delete (Window : access Completion_Window_Record'Class) is
   begin
      for J in 1 .. Window.Index - 1 loop
         Free (Window.Info (J));
      end loop;

      if Window.Mark /= null then
         Delete_Mark (Window.Buffer, Window.Mark);
      end if;

      Unchecked_Free (Window.Info);
      Destroy (Window.Notes_Window);
      Destroy (Window);
   end Delete;

   ----------------------
   -- Expand_Selection --
   ----------------------

   procedure Expand_Selection
     (Window      : access Completion_Window_Record'Class;
      UTF8_Filter : String;
      Number      : Natural)
   is
      Added : Natural := 0;
      Info  : Information_Record;
      Iter  : Gtk_Tree_Iter;

      function Is_Prefix (S1, S2 : String) return Boolean;
      --  Return True if S1 is a prefix of S2, case-sensitivity taken into
      --  account.

      ---------------
      -- Is_Prefix --
      ---------------

      function Is_Prefix (S1, S2 : String) return Boolean is
      begin
         if S1'Length = 0 then
            return True;
         end if;

         if S1'Length <= S2'Length then
            if Window.Case_Sensitive then
               return S2 (S2'First .. S2'First + S1'Length - 1) = S1;
            else
               return To_Lower (S2 (S2'First .. S2'First + S1'Length - 1))
                 = To_Lower (S1);
            end if;
         end if;

         return False;
      end Is_Prefix;

   begin
      if At_End (Window.Iter) then
         return;
      end if;

      if Window.More_Iter /= Null_Iter then
         Remove (Window.Model, Window.More_Iter);
         Window.More_Iter := Null_Iter;
      end if;

      if not Is_Valid (Window.Iter) then
         --  Since we don't know what happened before, we have to assume that
         --  the current iterator does not have a valid proposal anymore. In
         --  that case, we have to get the next element.
         Next  (Window.Iter);
      end if;

      while not At_End (Window.Iter) loop
         Info :=
           (new String'(To_Showable_String (Get_Proposal (Window.Iter))),
            new String'(Get_Completion (Get_Proposal (Window.Iter))),
            null,
            new Completion_Proposal'Class'(Get_Proposal (Window.Iter)),
            True);

         --  ??? some code duplication with Add_Contents
         Window.Info (Window.Index) := Info;
         Window.Index := Window.Index + 1;

         if Window.Index > Window.Info'Last then
            declare
               A : Information_Array (1 .. Window.Info'Last * 2);
            begin
               A (1 .. Window.Index - 1) :=
                 Window.Info (1 .. Window.Index - 1);
               Unchecked_Free (Window.Info);
               Window.Info := new Information_Array'(A);
            end;
         end if;
         --  ??? End of code duplication

         if Is_Prefix (UTF8_Filter, Info.Text.all) then
            --  ??? some code duplication with Add_Contents
            Append (Window.Model, Iter);
            Set (Window.Model, Iter, Markup_Column, Info.Markup.all);
            Set (Window.Model, Iter, Index_Column, Gint (Window.Index - 1));
            --  ??? End of code duplication

            Added := Added + 1;
         end if;

         Next (Window.Iter);
         exit when Added = Number;
      end loop;

      if not At_End (Window.Iter) then
         Append (Window.Model, Window.More_Iter);
         Set (Window.Model, Window.More_Iter, Markup_Column,
              "<span color=""grey""><i> (more...) </i></span>");
      end if;
   end Expand_Selection;

   ---------------------
   -- Adjust_Selected --
   ---------------------

   procedure Adjust_Selected
     (Window : access Completion_Window_Record'Class;
      UTF8   : String)
   is
      Prev   : Gtk_Tree_Iter;
      Curr   : Gtk_Tree_Iter;

      Selection : Gtk_Tree_Selection;
      Model     : Gtk_Tree_Model;

      Appended  : Natural := 0;

      Previously_Selected : Natural := 0;

      function Equals (A, B : String) return Boolean;
      --  Perform a case-conscious comparison.

      function Equals (A, B : String) return Boolean is
      begin
         if Window.Case_Sensitive then
            return A = B;
         else
            return To_Lower (A) = To_Lower (B);
         end if;
      end Equals;

   begin
      Selection := Get_Selection (Window.View);

      --  Find the entry currently being selected
      Get_Selected (Selection, Model, Curr);

      if Curr /= Null_Iter then
         Previously_Selected :=
           Natural (Get_Int (Window.Model, Curr, Index_Column));
      end if;

      --  Clear the model

      Clear (Window.Model);
      Window.More_Iter := Null_Iter;

      --  Browse through the completion possibilities and filter out the
      --  lines that don't match.

      Prev := Null_Iter;

      for J in 1 .. Window.Index - 1 loop
         if Window.Info (J).Text'Length >= UTF8'Length
           and then Equals
             (Window.Info (J).Text
              (Window.Info (J).Text'First
                 .. Window.Info (J).Text'First - 1 + UTF8'Length), UTF8)
         then
            Append (Window.Model, Curr);
            Appended := Appended + 1;

            Set (Window.Model, Curr, Markup_Column,
                 Window.Info (J).Markup.all);
            Set (Window.Model, Curr, Index_Column, Gint (J));

            if J = Previously_Selected then
               Iter_Copy (Curr, Prev);
            end if;
         end if;
      end loop;

      --  Expand the selection to show more items, if needed.
      if Appended < Minimal_Items_To_Show then
         Expand_Selection (Window, UTF8, Minimal_Items_To_Show - Appended);
      end if;

      --  Re-select the item previously selected, or, if there was none,
      --  select the first iter

      if Prev /= Null_Iter then
         Select_Iter (Selection, Prev);
      else
         Prev := Get_Iter_First (Window.Model);

         if Prev = Null_Iter then
            --  If there is no entry in the tree, delete the window.
            Delete (Window);
            return;
         else
            Select_Iter (Selection, Prev);
         end if;
      end if;
   end Adjust_Selected;

   ----------------------
   -- Mark_Set_Handler --
   ----------------------

   procedure Mark_Set_Handler
     (Window : access Completion_Window_Record'Class;
      Params : Glib.Values.GValues)
   is
      Mark : constant Gtk_Text_Mark :=
        Get_Text_Mark (Glib.Values.Nth (Params, 2));
      Cursor : Gtk_Text_Iter;
   begin
      if Get_Name (Mark) = "insert" then
         Get_Iter_At_Mark (Window.Buffer, Cursor, Mark);

         if Window.Initial_Line  /= Get_Line (Cursor) then
            Delete (Window);
         end if;
      end if;
   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception: " & Exception_Information (E));
   end Mark_Set_Handler;

   -------------------------
   -- Insert_Text_Handler --
   -------------------------

   procedure Insert_Text_Handler
     (Window : access Completion_Window_Record'Class;
      Params : Glib.Values.GValues)
   is
      Iter   : Gtk_Text_Iter;
      Beg    : Gtk_Text_Iter;

   begin
      if Window.In_Deletion then
         return;
      end if;

      Get_Text_Iter (Nth (Params, 1), Iter);
      Get_Iter_At_Mark (Window.Buffer, Beg, Window.Mark);
      Adjust_Selected (Window, Get_Text (Window.Buffer, Beg, Iter));
   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception: " & Exception_Information (E));
   end Insert_Text_Handler;

   --------------------------------
   -- Before_Delete_Text_Handler --
   --------------------------------

   procedure Before_Delete_Text_Handler
     (Window : access Completion_Window_Record'Class;
      Params : Glib.Values.GValues) is

      End_Iter : Gtk_Text_Iter;
      Cur      : Gtk_Text_Iter;
   begin
      if Window.In_Deletion then
         return;
      end if;

      Get_Text_Iter (Nth (Params, 2), End_Iter);
      Get_Iter_At_Mark (Window.Buffer, Cur, Get_Insert (Window.Buffer));

      if Get_Offset (End_Iter) > Get_Offset (Cur) then
         Window.In_Deletion := True;
         Delete (Window);
      end if;

   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception: " & Exception_Information (E));
   end Before_Delete_Text_Handler;

   -------------------------
   -- Delete_Text_Handler --
   -------------------------

   procedure Delete_Text_Handler
     (Window : access Completion_Window_Record'Class;
      Params : Glib.Values.GValues)
   is
      Iter     : Gtk_Text_Iter;
      Beg      : Gtk_Text_Iter;
   begin
      if Window.In_Deletion then
         return;
      end if;

      Get_Text_Iter (Nth (Params, 1), Iter);

      Get_Iter_At_Mark (Window.Buffer, Beg, Window.Mark);

      if Get_Offset (Iter) < Window.Initial_Offset then
         Delete (Window);
      else
         declare
            UTF8 : constant UTF8_String := Get_Text (Window.Buffer, Beg, Iter);
         begin
            Adjust_Selected (Window, UTF8);
         end;
      end if;

   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception: " & Exception_Information (E));
   end Delete_Text_Handler;

   -----------------------
   -- On_Button_Pressed --
   -----------------------

   function On_Button_Pressed
     (Window : access Completion_Window_Record'Class;
      Event  : Gdk_Event) return Boolean is
   begin
      if Get_Event_Type (Event) = Gdk_2button_Press then
         Complete_And_Exit (Window);
      end if;

      return False;
   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception: " & Exception_Information (E));
         return False;
   end On_Button_Pressed;

   --------------------------------
   -- On_Location_Button_Clicked --
   --------------------------------

   procedure On_Location_Button_Clicked
     (Window : access Completion_Window_Record'Class) is
   begin
      Open_File_Editor
        (Window.Kernel,
         Window.Location_Location.File_Path,
         Window.Location_Location.Line,
         Window.Location_Location.Column);
   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception: " & Exception_Information (E));
   end On_Location_Button_Clicked;

   --------------------------
   -- On_Selection_Changed --
   --------------------------

   procedure On_Selection_Changed
     (Window : access Completion_Window_Record'Class)
   is
      Sel   : Gtk_Tree_Selection;
      Iter  : Gtk_Tree_Iter;
      Path  : Gtk_Tree_Path;
      Model : Gtk_Tree_Model;
      Index : Natural;

      function Location_To_Label (Loc : File_Location) return String;
      --  Return a pango markup label corresponding to Loc.

      function Location_To_Label (Loc : File_Location) return String is
      begin
         if Loc.Column = 0 then
            return "<span color=""blue""><u>" & Base_Name (Loc.File_Path)
              & ":" & Loc.Line'Img & "</u></span>";
         else
            return "<span color=""blue""><u>" & Base_Name (Loc.File_Path)
              & ":" & Loc.Line'Img & ":" & Loc.Column'Img & "</u></span>";
         end if;
      end Location_To_Label;

   begin
      Sel := Get_Selection (Window.View);
      Get_Selected (Sel, Model, Iter);

      if Iter = Null_Iter then
         Hide_All (Window.Location_Title);
         Hide_All (Window.Location_Button);
         Set_Markup (Window.Location_Label, "");

      elsif Iter = Window.More_Iter then
         Path := Get_Path (Window.Model, Iter);

         if Prev (Path) then
            Iter := Get_Iter (Window.Model, Path);
            Expand_Selection (Window, "", Minimal_Items_To_Show);
            Select_Iter (Sel, Iter);
         end if;

      else
         Path := Get_Path (Model, Iter);
         Scroll_To_Cell (Window.View, Path, null, False, 0.1, 0.1);
         Path_Free (Path);

         Index := Natural (Get_Int (Window.Model, Iter, Index_Column));

         Show_All (Window.Notes_Window);

         if Window.Info (Index).Notes = null then
            if Window.Info (Index).Proposal /= null then
               Window.Info (Index).Notes := new String'
                 (Get_Documentation (Window.Info (Index).Proposal.all));
            end if;
         end if;

         declare
            Loc : File_Location :=
              Get_Location (Window.Info (Index).Proposal.all);
         begin
            if Loc = Null_File_Location then
               Hide_All (Window.Location_Title);
               Hide_All (Window.Location_Button);
               Set_Markup (Window.Location_Label, "");
            else
               Show_All (Window.Location_Title);
               Show_All (Window.Location_Button);
               Set_Markup
                 (Window.Location_Label, Location_To_Label (Loc));
            end if;

            Window.Location_Location := Loc;
         end;

         if Window.Info (Index).Notes.all = "" then
            Set_Markup
              (Window.Notes_Label, "<i>No documentation available</i>");
         else
            Set_Markup (Window.Notes_Label, Window.Info (Index).Notes.all);
         end if;
      end if;

   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception: " & Exception_Information (E));
   end On_Selection_Changed;

   ------------------
   -- On_Focus_Out --
   ------------------

   function On_Focus_Out
     (Window : access Completion_Window_Record'Class;
      Event  : Gdk_Event) return Boolean
   is
      pragma Unreferenced (Event);
   begin
      Delete (Window);
      return False;
   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception: " & Exception_Information (E));
         return False;
   end On_Focus_Out;

   ----------------------------
   -- Complete_Common_Prefix --
   ----------------------------

   function Complete_Common_Prefix
     (Window : access Completion_Window_Record'Class) return Boolean
   is
      Text_Begin : Gtk_Text_Iter;
      Text_End   : Gtk_Text_Iter;

      Iter : Gtk_Tree_Iter;
      J    : Natural;
   begin
      --  Compute the common prefix
      Iter := Get_Iter_First (Window.Model);

      if Iter = Null_Iter then
         return False;
      end if;

      J := Natural (Get_Int (Window.Model, Iter, Index_Column));

      Next (Window.Model, Iter);

      declare
         Prefix : constant String := Window.Info (J).Text.all;
         Last   : Natural := Prefix'Last;
         First  : constant Natural := Prefix'First;
      begin
         while Iter /= Null_Iter
           and then Iter /= Window.More_Iter
         loop
            J := Natural (Get_Int (Window.Model, Iter, Index_Column));

            for K in Window.Info (J).Text'First .. Natural'Min
              (Window.Info (J).Text'Last,
               Last - First + Window.Info (J).Text'First)
            loop
               if (Window.Case_Sensitive
                   and then Window.Info (J).Text (K) /= Prefix
                   (K - Window.Info (J).Text'First + First))
                 or else
                   To_Lower (Window.Info (J).Text (K)) /=
                 To_Lower (Prefix (K - Window.Info (J).Text'First + First))
               then
                  Last := K - Window.Info (J).Text'First + First - 1;
                  exit;
               end if;

               Last := K - Window.Info (J).Text'First + First;
            end loop;

            Next (Window.Model, Iter);
         end loop;

         --  Complete up to the common prefix
         Get_Iter_At_Mark (Window.Buffer, Text_Begin, Window.Mark);
         Get_Iter_At_Mark
           (Window.Buffer, Text_End, Get_Insert (Window.Buffer));

         if Get_Text (Window.Buffer, Text_Begin, Text_End)
           = Prefix (First .. Last)
         then
            return False;
         end if;

         Window.In_Deletion := True;
         Delete (Window.Buffer, Text_Begin, Text_End);
         Get_Iter_At_Mark (Window.Buffer, Text_Begin, Window.Mark);
         Insert (Window.Buffer, Text_Begin, Prefix (First .. Last));
         Window.In_Deletion := False;
      end;

      return True;
   end Complete_Common_Prefix;

   -----------------------
   -- Complete_And_Exit --
   -----------------------

   procedure Complete_And_Exit (Window : access Completion_Window_Record'Class)
   is
      Iter  : Gtk_Tree_Iter;
      Model : Gtk_Tree_Model;

      Pos        : Natural;
      Text_Begin : Gtk_Text_Iter;
      Text_End   : Gtk_Text_Iter;
   begin
      Get_Selected (Get_Selection (Window.View), Model, Iter);

      if Iter /= Null_Iter then
         Pos := Natural (Get_Int (Window.Model, Iter, Index_Column));

         Get_Iter_At_Mark (Window.Buffer, Text_Begin, Window.Mark);
         Get_Iter_At_Mark
           (Window.Buffer, Text_End, Get_Insert (Window.Buffer));

         Window.In_Deletion := True;
         Delete (Window.Buffer, Text_Begin, Text_End);

         Get_Iter_At_Mark (Window.Buffer, Text_Begin, Window.Mark);
         Insert (Window.Buffer, Text_Begin, Window.Info (Pos).Text.all);
      end if;

      Delete (Window);
   end Complete_And_Exit;

   ------------------
   -- On_Key_Press --
   ------------------

   function On_Key_Press
     (Window : access Completion_Window_Record'Class;
      Event  : Gdk_Event) return Boolean
   is
      Key   : Gdk_Key_Type;
      Sel   : Gtk_Tree_Selection;
      Iter  : Gtk_Tree_Iter;
      Model : Gtk_Tree_Model;
      Path  : Gtk_Tree_Path;

   begin
      Key := Get_Key_Val (Event);

      --  Case by case basis

      case Key is
         when GDK_Escape | GDK_Left | GDK_Right =>
            Delete (Window);
            return True;

         when GDK_Return =>
            Complete_And_Exit (Window);
            return True;

         when GDK_Down | GDK_KP_Down =>
            Sel := Get_Selection (Window.View);
            Get_Selected (Sel, Model, Iter);

            if Iter /= Null_Iter then
               Next (Window.Model, Iter);

               if Iter /= Null_Iter then
                  Select_Iter (Sel, Iter);
               end if;
            end if;

            return True;

         when GDK_Up | GDK_KP_Up =>
            Sel := Get_Selection (Window.View);
            Get_Selected (Sel, Model, Iter);
            Path := Get_Path (Window.Model, Iter);

            if Prev (Path) then
               Iter := Get_Iter (Window.Model, Path);
               Select_Iter (Sel, Iter);
            end if;

            Path_Free (Path);
            return True;

         when others =>
            null;
      end case;

      return False;

   exception
      when E : others =>
         Trace (Exception_Handle,
                "Unexpected exception: " & Exception_Information (E));
         return False;
   end On_Key_Press;

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New
     (Window : out Completion_Window_Access;
      Kernel : Kernel_Handle) is
   begin
      Window := new Completion_Window_Record;
      Completion_Window.Initialize (Window);
      Window.Kernel := Kernel;
   end Gtk_New;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (Window : access Completion_Window_Record'Class) is
      Col    : Gtk_Tree_View_Column;
      Text   : Gtk_Cell_Renderer_Text;
      Dummy  : Gint;
      Frame  : Gtk_Frame;
      Scroll : Gtk_Scrolled_Window;
      VBox   : Gtk_Vbox;
      HBox   : Gtk_Hbox;
      Viewport : Gtk_Viewport;

      pragma Unreferenced (Dummy);
   begin
      Gtk.Window.Initialize (Window, Window_Popup);
      Set_Decorated (Window, False);

      Gtk_New (Window.Model, Column_Types);
      Gtk_New (Window.View, Window.Model);
      Set_Headers_Visible (Window.View, False);

      Gtk_New (Col);
      Dummy := Append_Column (Window.View, Col);

      Gtk_New (Text);
      Pack_Start (Col, Text, True);
      Add_Attribute (Col, Text, "markup", Markup_Column);

      Gtk_New (Frame);
      Add (Window, Frame);

      Gtk_New (Window.Tree_Scroll);
      Set_Policy (Window.Tree_Scroll, Policy_Automatic, Policy_Automatic);
      Add (Window.Tree_Scroll, Window.View);
      Add (Frame, Window.Tree_Scroll);

      Window.Info := new Information_Array (1 .. 1024);
      Window.Index := 1;

      --  Create the Notes window

      Gtk_New (Window.Notes_Window, Window_Popup);
      Gtk_New (Window.Notes_Label);
      Set_Line_Wrap (Window.Notes_Label, False);
      Set_Use_Markup (Window.Notes_Label, True);
      Gtk_New_Vbox (VBox);
      Gtk_New (Frame);
      Gtk_New (Scroll);
      Set_Policy (Scroll, Policy_Automatic, Policy_Automatic);
      Add (Frame, Scroll);
      Add (Window.Notes_Window, Frame);
      Gtk_New (Viewport);
      Set_Shadow_Type (Viewport, Shadow_None);
      Add (Scroll, Viewport);
      Add (Viewport, VBox);

      Gtk_New_Hbox (HBox);
      Pack_Start (VBox, HBox, False, False, 3);

      Gtk_New (Window.Location_Title);
      Set_Use_Markup (Window.Location_Title, True);
      Set_Markup (Window.Location_Title, "<b>Declaration at: </b>");
      Pack_Start (HBox, Window.Location_Title, False, False, 3);

      Gtk_New (Window.Location_Button, "");
      Gtk_New (Window.Location_Label);
      Pack_Start (HBox, Window.Location_Button, False, False, 3);
      Add (Window.Location_Button, Window.Location_Label);
      Set_Use_Markup (Window.Location_Label, True);

      Set_Relief (Window.Location_Button, Relief_None);
      Object_Connect
        (Window.Location_Button, "clicked",
         To_Marshaller (On_Location_Button_Clicked'Access), Window,
         After => False);

      Gtk_New_Hbox (HBox);
      Pack_Start (VBox, HBox, False, False, 3);
      Pack_Start (HBox, Window.Notes_Label, False, False, 3);
   end Initialize;

   ------------------
   -- Add_Contents --
   ------------------

   procedure Add_Contents
     (Window     : Completion_Window_Access;
      Markup     : String;
      Completion : String;
      Notes      : String)
   is
      Iter : Gtk_Tree_Iter;
      Info : Information_Record;
   begin
      Info :=
        (new String'(Markup),
         new String'(Completion),
         new String'(Notes),
         null,
         True);

      Window.Info (Window.Index) := Info;
      Window.Index := Window.Index + 1;

      if Window.Index > Window.Info'Last then
         declare
            A : Information_Array (1 .. Window.Info'Last * 2);
         begin
            A (1 .. Window.Index - 1) := Window.Info (1 .. Window.Index - 1);
            Unchecked_Free (Window.Info);
            Window.Info := new Information_Array'(A);
         end;
      end if;

      Append (Window.Model, Iter);
      Set (Window.Model, Iter, Markup_Column, Markup);
      Set (Window.Model, Iter, Index_Column, Gint (Window.Index - 1));
   end Add_Contents;

   ----------
   -- Show --
   ----------

   procedure Show
     (Window         : Completion_Window_Access;
      View           : Gtk_Text_View;
      Buffer         : Gtk_Text_Buffer;
      Iter           : Gtk_Text_Iter;
      Case_Sensitive : Boolean;
      Complete       : Boolean)
   is
      Iter_Coords : Gdk_Rectangle;
      Window_X, Window_Y : Gint;
      Gdk_X, Gdk_Y       : Gint;
      Dummy              : Boolean;
      Dummy2             : Boolean;
      pragma Unreferenced (Dummy2);

      Rows               : Gint;
      Width, Height      : Gint;
      X, Y               : Gint;
      Requisition        : Gtk_Requisition;

      Dummy_X, Dummy_Y, D     : Gint;
      Root_Width, Root_Height : Gint;

      Cursor                  : Gtk_Text_Iter;
      Max_Width, Notes_Window_Width, Max_Height : Gint;
      Tree_Iter               : Gtk_Tree_Iter;
   begin
      Window.Text := View;
      Window.Buffer := Buffer;
      Window.Mark := Create_Mark (Buffer, "", Iter);

      Get_Iter_At_Mark (Buffer, Cursor, Get_Insert (Buffer));
      Window.Initial_Offset := Get_Offset (Cursor);
      Window.Initial_Line   := Get_Line (Cursor);

      Window.Case_Sensitive := Case_Sensitive;

      --  Set the position.

      Get_Iter_Location (View, Iter, Iter_Coords);

      Buffer_To_Window_Coords
        (View, Text_Window_Text,
         Iter_Coords.X,
         Iter_Coords.Y + Iter_Coords.Height + 1,
         Window_X, Window_Y);

      Get_Desk_Relative_Origin
        (Get_Window (View, Text_Window_Text), Gdk_X, Gdk_Y, Dummy);
      --  ??? should we check for the result ?

      --  Compute the placement of the window.

      Size_Request (Window.View, Requisition);
      Requisition := Get_Child_Requisition (Window.View);

      --  ??? Uposition should take into account the current desktop.

      declare
         Font : constant Pango_Font_Description :=
           Get_Font_Description (Get_Style (View));
         Char_Width, Char_Height : Gint;
         Layout : Pango_Layout;
      begin
         Modify_Font (Window.View, Font);
         Modify_Font (Window.Notes_Label, Font);

         Layout := Create_Pango_Layout (Window.View);
         Set_Font_Description (Layout, Font);
         Set_Text (Layout, "0m");
         Get_Pixel_Size (Layout, Char_Width, Char_Height);
         Unref (Layout);

         Max_Width := Char_Width * 20;
         Max_Height := Char_Height * 20;
         Notes_Window_Width := Max_Width * 2;
      end;

      --  Compute the real width and height of the window

      Width := Gint'Min (Max_Window_Width, Max_Width) + 5;

      if Requisition.Height > Max_Height then
         --  Display an integer number of lines in the tree view.
         Rows := (Gint (Window.Index - 1) * (Max_Height)) / Requisition.Height;
         Height := Rows * (Requisition.Height / Gint (Window.Index - 1)) + 5;
      else
         Height := Max_Height + 5;
      end if;

      Set_Default_Size (Window, Width, Height);

      --  Compute the coordinates of the window so that it doesn't get past
      --  the screen border.
      Get_Geometry (Null_Window, Dummy_X, Dummy_Y, Root_Width, Root_Height, D);
      X := Gint'Min (Gdk_X + Window_X, Root_Width - Width);
      Y := Gint'Min (Gdk_Y + Window_Y, Root_Height - Height);

      Set_UPosition (Window, X, Y);

      --  Compute the size and position of the Notes window.

      Set_Default_Size (Window.Notes_Window, Notes_Window_Width, Height);

      if Root_Width - (X + Width + 4) > Notes_Window_Width then
         Set_UPosition (Window.Notes_Window, X + Width, Y);
      else
         --  Make sure the Notes window doesn't overlap the tree view.
         if X <= Notes_Window_Width then
            Notes_Window_Width := X - 2;
            Set_Default_Size (Window.Notes_Window, Notes_Window_Width, Height);
         end if;

         Set_UPosition (Window.Notes_Window, X - Notes_Window_Width, Y);
      end if;

      Show_All (Window);
      Hide_All (Get_Vscrollbar (Window.Tree_Scroll));

      Grab_Focus (Window.Text);

      Object_Connect
        (Window.Text, "focus_out_event",
         To_Marshaller (On_Focus_Out'Access), Window, After => False);

      Object_Connect
        (Window.Text, "button_press_event",
         To_Marshaller (On_Focus_Out'Access), Window, After => False);

      Object_Connect
        (Window.Text, "key_press_event",
         To_Marshaller (On_Key_Press'Access), Window, After => False);

      Object_Connect
        (Buffer, "insert_text", Insert_Text_Handler'Access, Window,
         After => True);

      Object_Connect (Buffer, "mark_set", Mark_Set_Handler'Access, Window);

      Object_Connect
        (Buffer, "delete_range", Delete_Text_Handler'Access, Window,
         After => True);

      Object_Connect
        (Buffer, "delete_range", Before_Delete_Text_Handler'Access, Window,
         After => False);

      Object_Connect
        (Window.View, "button_press_event",
         To_Marshaller (On_Button_Pressed'Access), Window,
         After => False);

      Object_Connect
        (Get_Selection (Window.View), "changed",
         To_Marshaller (On_Selection_Changed'Access), Window,
         After => True);

      Expand_Selection (Window, "", Minimal_Items_To_Show);

      Tree_Iter := Get_Iter_First (Window.Model);

      if Tree_Iter = Null_Iter then
         Delete (Window);
         return;
      else
         Select_Iter (Get_Selection (Window.View), Tree_Iter);
      end if;

      On_Selection_Changed (Window);

      if Complete then
         Dummy2 := Complete_Common_Prefix (Window);
      end if;
   end Show;

   -----------------
   -- Select_Next --
   -----------------

   procedure Select_Next (Window : Completion_Window_Access) is
      Sel   : Gtk_Tree_Selection;
      Iter  : Gtk_Tree_Iter;
      Model : Gtk_Tree_Model;
   begin
      if not Complete_Common_Prefix (Window) then
         Sel := Get_Selection (Window.View);
         Get_Selected (Sel, Model, Iter);

         if Iter /= Null_Iter then
            Next (Window.Model, Iter);

            if Iter = Null_Iter then
               Iter := Get_Iter_First (Window.Model);
            end if;
         end if;

         --  Iter can be null here if there is an exception returned by the
         --  completion engine, when expanding the completions list, for
         --  instance.
         --  Add protection against this, since calling Select_Iter with an
         --  empty iter can cause a storage_error.
         if Iter /= Null_Iter then
            Select_Iter (Sel, Iter);
         end if;
      end if;
   end Select_Next;

   -----------------------------
   -- Set_Completion_Iterator --
   -----------------------------

   procedure Set_Completion_Iterator
     (Window : Completion_Window_Access;
      Iter   : Completion_Iterator) is
   begin
      Window.Iter := Iter;
   end Set_Completion_Iterator;

end Completion_Window;
