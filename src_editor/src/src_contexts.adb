-----------------------------------------------------------------------
--                              G P S                                --
--                                                                   --
--                     Copyright (C) 2001-2002                       --
--                            ACT-Europe                             --
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
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Ada.Unchecked_Deallocation;
with Ada.Exceptions;            use Ada.Exceptions;
with Ada.Characters.Handling;   use Ada.Characters.Handling;
with Gtkada.MDI;                use Gtkada.MDI;
with Gtk.Box;                   use Gtk.Box;
with Gtk.Combo;                 use Gtk.Combo;
with Gtk.Frame;                 use Gtk.Frame;
with Gtk.GEntry;                use Gtk.GEntry;
with Gtk.Check_Button;          use Gtk.Check_Button;
with Gtk.Enums;                 use Gtk.Enums;
with Gtk.Label;                 use Gtk.Label;
with Gtk.Table;                 use Gtk.Table;
with Gtk.Tooltips;              use Gtk.Tooltips;
with Gtk.Widget;                use Gtk.Widget;
with Files_Extra_Info_Pkg;      use Files_Extra_Info_Pkg;
with Osint;                     use Osint;
with Prj_API;                   use Prj_API;
with Basic_Types;               use Basic_Types;
with Glide_Kernel;              use Glide_Kernel;
with Glide_Kernel.Project;      use Glide_Kernel.Project;
with Glide_Kernel.Console;      use Glide_Kernel.Console;
with Glide_Kernel.Modules;      use Glide_Kernel.Modules;
with File_Utils;                use File_Utils;
with String_Utils;              use String_Utils;
with Traces;                    use Traces;
with GNAT.Regpat;               use GNAT.Regpat;
with GNAT.Regexp;               use GNAT.Regexp;
with GNAT.OS_Lib;               use GNAT.OS_Lib;
with GNAT.Directory_Operations; use GNAT.Directory_Operations;
with Language;                  use Language;
with Language_Handlers;         use Language_Handlers;
with OS_Utils;                  use OS_Utils;
with Find_Utils;                use Find_Utils;
with Glide_Intl;                use Glide_Intl;
with GUI_Utils;                 use GUI_Utils;

with Src_Editor_Box;            use Src_Editor_Box;
with Src_Editor_Module;         use Src_Editor_Module;

package body Src_Contexts is

   Me : constant Debug_Handle := Create ("Src_Contexts");

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (Match_Result, Match_Result_Access);
   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (Match_Result_Array, Match_Result_Array_Access);

   type Recognized_Lexical_States is
     (Statements, Strings, Mono_Comments, Multi_Comments);
   --  Current lexical state of the currently parsed file.
   --
   --  Statements      all but comments and strings
   --  Strings         string literals
   --  Mono_Comments   end of line terminated comments
   --  Multi_Comments  (possibly) multi-line comments

   procedure Scan_Buffer
     (Buffer   : String;
      Context  : access Search_Context'Class;
      Callback : Scan_Callback;
      Scope      : Search_Scope;
      Lang     : Language_Access := null);
   --  Search Context in buffer, searching only in the appropriate scope.
   --  Buffer is assumed to contain complete contexts (e.g the contents of
   --  a whole file).

   procedure Scan_File
     (Context  : access Search_Context'Class;
      Kernel   : access Kernel_Handle_Record'Class;
      Name     : String;
      Callback : Scan_Callback;
      Scope    : Search_Scope);
   --  Search Context in the file Name, searching only in the appropriate
   --  scope.

   function Scan_And_Store
     (Context  : access Search_Context'Class;
      Kernel   : access Kernel_Handle_Record'Class;
      Str      : String;
      Is_File  : Boolean;
      Scope    : Search_Scope;
      Lang     : Language_Access := null) return Match_Result_Array_Access;
   --  Same as above, but behaves as if there was a default callback that
   --  prints the result in the Glide console.
   --  Str can be either a file name or a file contents, depending whether
   --  Is_File is resp. True or False.
   --  It returns the list of matches that were found in the buffer, or null if
   --  no match was found. It is the responsability of the caller to free the
   --  returned array.

   function Scan_Next
     (Context        : access Search_Context'Class;
      Kernel         : access Kernel_Handle_Record'Class;
      Editor         : access Source_Editor_Box_Record'Class;
      Scope          : Search_Scope;
      Lang           : Language_Access;
      Current_Line   : Integer;
      Current_Column : Integer;
      Backward       : Boolean) return Match_Result_Access;
   --  Return the next occurrence of Context in Editor, just before or just
   --  after Current_Line, Current_Column. If no match is found after the
   --  current position, for a forward search, return the first occurrence from
   --  the beginning of the editor. Likewise for a backward search.
   --  Note that the index in the result might be incorrect, although the line
   --  and column will always be correct.
   --  null is returned if there is no match.

   procedure Highlight_Result
     (Kernel      : access Kernel_Handle_Record'Class;
      File_Name   : String;
      Match       : Match_Result;
      Interactive : Boolean);
   --  Print the result of the search in the glide console

   function End_Of_Line (Buffer : String; Pos : Natural) return Integer;
   pragma Inline (End_Of_Line);
   --  Return the index for the end of the line containing Pos

   function Is_Word_Delimiter (C : Character) return Boolean;
   pragma Inline (Is_Word_Delimiter);
   --  Return True if C is a character which can't be in a word.

   procedure Free (Result : in out Match_Result_Array_Access);
   --  Free Result and its components

   procedure Initialize_Scope_Combo
     (Combo  : access Gtk_Combo_Record'Class;
      Kernel : access Kernel_Handle_Record'Class);
   --  Initialize the combo box with all the entries for the selection of the
   --  scope.

   procedure Auxiliary_Search
     (Context         : access Current_File_Context;
      Editor          : Source_Editor_Box;
      Kernel          : access Glide_Kernel.Kernel_Handle_Record'Class;
      Search_Backward : Boolean;
      Success         : out Boolean);
   --  Auxiliary function, factorizes code between Search and Replace.

   -----------------------
   -- Is_Word_Delimiter --
   -----------------------

   function Is_Word_Delimiter (C : Character) return Boolean is
   begin
      return not (Is_Alphanumeric (C) or else C = '_');
   end Is_Word_Delimiter;

   -----------------
   -- End_Of_Line --
   -----------------

   function End_Of_Line (Buffer : String; Pos : Natural) return Integer is
      J : Integer := Pos;
   begin
      while J < Buffer'Last loop
         if Buffer (J) = ASCII.LF then
            return J - 1;
         end if;

         J := J + 1;
      end loop;

      return Buffer'Last;
   end End_Of_Line;

   -----------------
   -- Scan_Buffer --
   -----------------

   procedure Scan_Buffer
     (Buffer     : String;
      Context    : access Search_Context'Class;
      Callback   : Scan_Callback;
      Scope      : Search_Scope;
      Lang       : Language_Access := null)
   is
      Scanning_Allowed : constant array (Recognized_Lexical_States) of Boolean
        := (Statements     => Scope = Whole or else Scope = All_But_Comments,
            Strings        => Scope = Whole
              or else Scope in Comments_And_Strings .. All_But_Comments,
            Mono_Comments  => Scope in Whole .. Comments_And_Strings,
            Multi_Comments => Scope in Whole .. Comments_And_Strings);
      --  Indicates what lexical states are valid, depending on the current
      --  scope.

      procedure Next_Scope_Transition
        (Buffer      : String;
         Pos         : in out Positive;
         State       : in out Recognized_Lexical_States;
         Section_End : out Integer;
         Lang        : Language_Context);
      --  Move Pos to the first character in buffer that isn't in the same
      --  lexical state as State (ie if State is one we want to search in, then
      --  Pos will be left on the first character we do not want to search).
      --
      --  Pos is purely internal, and represents the first character into the
      --  next section (ie after passing the section start string, like -- for
      --  comments). Section_End on the last point in the current section.

      ---------------------------
      -- Next_Scope_Transition --
      ---------------------------

      procedure Next_Scope_Transition
        (Buffer      : String;
         Pos         : in out Positive;
         State       : in out Recognized_Lexical_States;
         Section_End : out Integer;
         Lang        : Language_Context)
      is
         Str_Delim     : Character renames Lang.String_Delimiter;
         Quote_Char    : Character renames Lang.Quote_Character;
         NL_Comm_Start : String    renames Lang.New_Line_Comment_Start;
         M_Comm_Start  : String    renames Lang.Comment_Start;
         M_Comm_End    : String    renames Lang.Comment_End;
         Char_Delim    : Character renames Lang.Constant_Character;

         Looking_For : constant Boolean := not Scanning_Allowed (State);
         --  Whether the final range should or should not be scanned.

      begin
         while Pos <= Buffer'Last
           and then Scanning_Allowed (State) /= Looking_For
         loop
            case State is
               --  Statements end on any other state

               when Statements =>
                  while Pos <= Buffer'Last loop
                     if M_Comm_Start'Length /= 0
                       and then Pos + M_Comm_Start'Length - 1 <= Buffer'Last
                       and then Buffer (Pos .. Pos + M_Comm_Start'Length - 1) =
                       M_Comm_Start
                     then
                        State := Multi_Comments;
                        Section_End := Pos - 1;
                        Pos := Pos + M_Comm_Start'Length;
                        exit;

                     elsif NL_Comm_Start'Length /= 0
                       and then Pos + NL_Comm_Start'Length - 1 <= Buffer'Last
                       and then Buffer (Pos .. Pos + NL_Comm_Start'Length - 1)
                       = NL_Comm_Start
                     then
                        State := Mono_Comments;
                        Section_End := Pos - 1;
                        Pos := Pos + NL_Comm_Start'Length;
                        exit;

                     elsif Buffer (Pos) = Str_Delim
                       and then (Pos = Buffer'First
                                 or else Pos = Buffer'Last
                                 or else Buffer (Pos - 1) /= Char_Delim
                                 or else Buffer (Pos + 1) /= Char_Delim)
                     then
                        State := Strings;
                        Section_End := Pos - 1;
                        Pos := Pos + 1;
                        exit;
                     end if;

                     Pos := Pos + 1;
                  end loop;

               --  Strings end on string delimiters

               when Strings =>
                  while Pos <= Buffer'Last loop
                     if Buffer (Pos) = Str_Delim
                       and then (Quote_Char = ASCII.NUL or else
                                 (Pos > Buffer'First and then
                                  Buffer (Pos - 1) /= Quote_Char))
                     then
                        State := Statements;
                        Section_End := Pos - 1;
                        Pos := Pos + 1;
                        exit;
                     end if;

                     Pos := Pos + 1;
                  end loop;

               --  Single line comments end on ASCII.LF characters

               when Mono_Comments =>
                  while Pos <= Buffer'Last
                    and then Buffer (Pos) /= ASCII.LF
                  loop
                     Pos := Pos + 1;
                  end loop;

                  Section_End := Pos - 1;
                  if Pos <= Buffer'Last then
                     Pos := Pos + 1;
                  end if;
                  State := Statements;

               --  Multi-line comments end with specific sequences

               when Multi_Comments =>
                  while Pos <= Buffer'Last loop
                     if M_Comm_End'Length /= 0
                       and then Pos + M_Comm_End'Length - 1 <= Buffer'Last
                       and then Buffer (Pos .. Pos + M_Comm_End'Length - 1) =
                       M_Comm_End
                     then
                        State := Statements;
                        Section_End := Pos - 1;
                        Pos := Pos + M_Comm_End'Length;
                        exit;
                     end if;

                     Pos := Pos + 1;
                  end loop;
            end case;
         end loop;

         if Pos > Buffer'Last then
            Section_End := Buffer'Last;
         end if;
      end Next_Scope_Transition;

      Pos           : Positive := 1;
      Line_Start    : Positive;
      Line          : Natural := 1;
      Column        : Natural := 1;
      Last_Index    : Positive := 1;
      Section_End   : Integer;
      Lexical_State : Recognized_Lexical_States := Statements;
      Old_State     : Recognized_Lexical_States;

   begin  --  Scan_Buffer
      if Buffer'Length = 0 then
         return;
      end if;

      --  If the language is null, we simply use the more efficient algorithm

      if Scope = Whole or else Lang = null then
         Scan_Buffer_No_Scope
           (Context,
            Buffer,
            Callback,
            Pos, Line, Column);
         return;
      end if;

      declare
         Language : constant Language_Context := Get_Language_Context (Lang);
      begin
         --  Always find the longest possible range, so that we can benefit
         --  as much as possible from the efficient string searching
         --  algorithms.

         while Pos <= Buffer'Last loop
            Line_Start := Pos;
            Old_State  := Lexical_State;

            Next_Scope_Transition
              (Buffer, Pos, Lexical_State, Section_End, Language);

            if Scanning_Allowed (Old_State) then
               Scan_Buffer_No_Scope
                 (Context, Buffer (Line_Start .. Section_End),
                  Callback, Last_Index, Line, Column);
            end if;

            for J in Last_Index .. Pos - 1 loop
               if Buffer (J) = ASCII.LF then
                  Line := Line + 1;
                  Column := 0;
               else
                  Column := Column + 1;
               end if;
            end loop;

            Last_Index := Pos;
         end loop;
      end;
   end Scan_Buffer;

   ---------------
   -- Scan_File --
   ---------------

   procedure Scan_File
     (Context  : access Search_Context'Class;
      Kernel   : access Kernel_Handle_Record'Class;
      Name     : String;
      Callback : Scan_Callback;
      Scope    : Search_Scope)
   is
      Max_File_Len  : constant := 2 ** 21;
      FD            : File_Descriptor;
      Lang          : Language_Access;
      Len           : Natural;
      Buffer        : Basic_Types.String_Access;
      Child         : MDI_Child;

   begin
      --  ??? Would be nice to handle backward search, which is extremely hard
      --  with regular expressions

      Lang := Get_Language_From_File (Get_Language_Handler (Kernel), Name);

      --  If there is already an open editor, that might contain local
      --  modification, use its contents, otherwise read the buffer from the
      --  file itself.

      Child := Get_File_Editor (Kernel, Name);

      if Child = null then
         FD := Open_Read (Name, Text);
         if FD = Invalid_FD then
            return;
         end if;

         Len := Natural (File_Length (FD));

         --  ??? Temporary, until we are sure that we only manipulate text
         --  files.

         if Len > Max_File_Len then
            Close (FD);
            return;
         end if;

         Buffer := new String (1 .. Len);
         Len := Read (FD, Buffer.all'Address, Len);
         Close (FD);

      else
         Buffer := new String'
           (Get_Slice (Get_Source_Box_From_MDI (Child), 1, 1));
         Len := Buffer'Last;
      end if;

      Scan_Buffer (Buffer (1 .. Len), Context, Callback, Scope, Lang);
      Free (Buffer);

   exception
      when Invalid_Context =>
         Close (FD);
         Free (Buffer);
   end Scan_File;

   ----------------------
   -- Highlight_Result --
   ----------------------

   procedure Highlight_Result
     (Kernel      : access Kernel_Handle_Record'Class;
      File_Name   : String;
      Match       : Match_Result;
      Interactive : Boolean)
   is
      function To_Positive (N : Natural) return Positive;
      --  If N > 0 then return N else return 1.

      function To_Positive (N : Natural) return Positive is
      begin
         if N = 0 then
            return 1;
         else
            return Positive (N);
         end if;
      end To_Positive;

   begin
      if Interactive then
         Open_File_Editor
           (Kernel,
            File_Name,
            To_Positive (Match.Line), To_Positive (Match.Column),
            To_Positive (Match.End_Column));
      else
         Insert_Result
           (Kernel,
            -"Search Results",
            File_Name,
            Match.Text,
            To_Positive (Match.Line), To_Positive (Match.Column),
            Match.End_Column - Match.Column);
      end if;
   end Highlight_Result;

   ---------------
   -- Scan_Next --
   ---------------

   function Scan_Next
     (Context        : access Search_Context'Class;
      Kernel         : access Kernel_Handle_Record'Class;
      Editor         : access Source_Editor_Box_Record'Class;
      Scope          : Search_Scope;
      Lang           : Language_Access;
      Current_Line   : Integer;
      Current_Column : Integer;
      Backward       : Boolean) return Match_Result_Access
   is
      Result : Match_Result_Access := null;
      Continue_Till_End : Boolean := False;

      function Stop_At_First_Callback (Match : Match_Result) return Boolean;
      --  Stop at the first match encountered

      function Backward_Callback (Match : Match_Result) return Boolean;
      --  Return the last match just before Current_Line and Current_Column

      function Stop_At_First_Callback (Match : Match_Result) return Boolean is
      begin
         Result := new Match_Result'(Match);
         return False;
      end Stop_At_First_Callback;

      function Backward_Callback (Match : Match_Result) return Boolean is
      begin
         --  If we have already found a match, and the current one is after the
         --  current position, we can stop there. Else, if we have passed the
         --  current position but don't have any match yet, we have to return
         --  the last match.
         if Match.Line > Current_Line
           or else (Match.Line = Current_Line
                    and then Match.End_Column >= Current_Column)
         then
            if not Continue_Till_End
              and then Result /= null
            then
               return False;
            end if;

            Continue_Till_End := True;
         end if;

         Unchecked_Free (Result);
         Result := new Match_Result'(Match);
         return True;
      end Backward_Callback;

   begin
      if Backward then
         Scan_Buffer
           (Get_Slice (Editor, 1, 1), Context,
            Backward_Callback'Unrestricted_Access, Scope, Lang);
      else
         Scan_Buffer
           (Get_Slice (Editor, Current_Line, Current_Column), Context,
            Stop_At_First_Callback'Unrestricted_Access, Scope, Lang);

         --  Start from the beginning if necessary
         if Result = null then
            Raise_Console (Kernel);
            Insert (Kernel, -"No more matches, starting from beginning");
            Scan_Buffer
              (Get_Slice (Editor, 1, 1), Context,
               Stop_At_First_Callback'Unrestricted_Access, Scope, Lang);
         else
            if Result.Line = 1 then
               Result.Column     := Result.Column + Current_Column - 1;
               Result.End_Column := Result.End_Column + Current_Column - 1;
            end if;

            Result.Line := Result.Line + Current_Line - 1;
         end if;
      end if;

      return Result;
   end Scan_Next;

   --------------------
   -- Scan_And_Store --
   --------------------

   function Scan_And_Store
     (Context  : access Search_Context'Class;
      Kernel   : access Kernel_Handle_Record'Class;
      Str      : String;
      Is_File  : Boolean;
      Scope    : Search_Scope;
      Lang     : Language_Access := null) return Match_Result_Array_Access
   is
      Result : Match_Result_Array_Access := null;

      function Callback (Match : Match_Result) return Boolean;
      --  Save Match in the result array.

      function Callback (Match : Match_Result) return Boolean is
         Tmp  : Match_Result_Array_Access;
      begin
         Tmp := Result;
         if Tmp = null then
            Result := new Match_Result_Array (1 .. 1);
         else
            Result := new Match_Result_Array (1 .. Tmp'Last + 1);
         end if;

         if Tmp /= null then
            Result (1 .. Tmp'Last) := Tmp.all;
            Unchecked_Free (Tmp);
         end if;

         Result (Result'Last) := new Match_Result'(Match);
         return True;
      end Callback;

   begin
      if Is_File then
         Scan_File (Context, Kernel, Str, Callback'Unrestricted_Access, Scope);
      else
         Scan_Buffer (Str, Context, Callback'Unrestricted_Access, Scope, Lang);
      end if;

      return Result;
   end Scan_And_Store;

   ----------
   -- Free --
   ----------

   procedure Free (Result : in out Match_Result_Array_Access) is
   begin
      if Result /= null then
         for R in Result'Range loop
            Unchecked_Free (Result (R));
         end loop;

         Unchecked_Free (Result);
      end if;
   end Free;

   procedure Free (Context : in out Current_File_Context) is
   begin
      Free (Context.Next_Matches_In_File);
   end Free;

   procedure Free (Context : in out Files_Context) is
   begin
      Directory_List.Free (Context.Dirs);
      Free (Context.Directory);
      Free (Context.Current_File);
      Free (Context.Next_Matches_In_File);
      Free (Search_Context (Context));
   end Free;

   procedure Free (Context : in out Files_Project_Context) is
   begin
      Free (Context.Files);
      Free (Context.Next_Matches_In_File);
      Free (Search_Context (Context));
   end Free;

   -------------------
   -- Set_File_List --
   -------------------

   procedure Set_File_List
     (Context : access Files_Project_Context;
      Files   : Basic_Types.String_Array_Access) is
   begin
      Free (Context.Files);
      Free (Context.Next_Matches_In_File);
      Context.Files := Files;
      Context.Current_File := Context.Files'First;
   end Set_File_List;

   -------------------
   -- Set_File_List --
   -------------------

   procedure Set_File_List
     (Context       : access Files_Context;
      Files_Pattern : GNAT.Regexp.Regexp;
      Directory     : String  := "";
      Recurse       : Boolean := False) is
   begin
      Free (Context.Directory);
      Free (Context.Next_Matches_In_File);
      Context.Files_Pattern := Files_Pattern;
      Context.Recurse := Recurse;

      if Directory = "" then
         Context.Directory := new String'(Get_Current_Dir);
      else
         Context.Directory := new String'(Name_As_Directory (Directory));
      end if;
   end Set_File_List;

   --------------------------
   -- Current_File_Factory --
   --------------------------

   function Current_File_Factory
     (Kernel             : access Glide_Kernel.Kernel_Handle_Record'Class;
      All_Occurrences    : Boolean;
      Extra_Information  : Gtk.Widget.Gtk_Widget)
      return Search_Context_Access
   is
      Context  : Current_File_Context_Access;
      Context2 : Files_Project_Context_Access;
      Scope   : constant Scope_Selector := Scope_Selector (Extra_Information);
      Child    : MDI_Child;
      Editor   : Source_Editor_Box;

   begin
      --  If we are looking for all the occurrences, we simply reuse another
      --  context, instead of the interactive Current_File_Context
      if All_Occurrences then
         Child := Find_Current_Editor (Kernel);
         if Child = null then
            return null;
         end if;

         Context2 := new Files_Project_Context;
         Context2.Scope := Search_Scope'Val (Get_Index_In_List (Scope.Combo));

         Editor := Get_Source_Box_From_MDI (Child);

         Set_File_List
           (Context2, new String_Array'
              (1 => new String'(Get_Filename (Editor))));
         return Search_Context_Access (Context2);

      else
         Context := new Current_File_Context;
         Context.All_Occurrences := False;
         Context.Scope := Search_Scope'Val
           (Get_Index_In_List (Scope.Combo));
         return Search_Context_Access (Context);
      end if;
   end Current_File_Factory;

   --------------------------------
   -- Files_From_Project_Factory --
   --------------------------------

   function Files_From_Project_Factory
     (Kernel             : access Glide_Kernel.Kernel_Handle_Record'Class;
      All_Occurrences    : Boolean;
      Extra_Information  : Gtk.Widget.Gtk_Widget)
      return Search_Context_Access
   is
      pragma Unreferenced (All_Occurrences);
      Context : Files_Project_Context_Access;
      Scope   : constant Scope_Selector := Scope_Selector (Extra_Information);
   begin
      Context := new Files_Project_Context;
      Context.Scope := Search_Scope'Val (Get_Index_In_List (Scope.Combo));

      Set_File_List
        (Context,
         Get_Source_Files (Get_Project_View (Kernel), True));
      return Search_Context_Access (Context);
   end Files_From_Project_Factory;

   -------------------
   -- Files_Factory --
   -------------------

   function Files_Factory
     (Kernel             : access Glide_Kernel.Kernel_Handle_Record'Class;
      All_Occurrences    : Boolean;
      Extra_Information  : Gtk.Widget.Gtk_Widget)
      return Search_Context_Access
   is
      pragma Unreferenced (Kernel, All_Occurrences);

      Context : Files_Context_Access;
      Extra   : constant Files_Extra_Scope := Files_Extra_Scope
        (Extra_Information);
      Re      : GNAT.Regexp.Regexp;

   begin
      if Get_Text (Extra.Files_Entry) /= "" then
         Context := new Files_Context;

         Context.Scope := Search_Scope'Val (Get_Index_In_List (Extra.Combo));

         Re := Compile
           (Get_Text (Extra.Files_Entry),
            Glob => True,
            Case_Sensitive => Integer (Get_File_Names_Case_Sensitive) /= 0);
         Set_File_List
           (Context,
            Files_Pattern => Re,
            Directory     => Get_Text (Extra.Directory_Entry),
            Recurse       => Get_Active (Extra.Subdirs_Check));
         return Search_Context_Access (Context);
      end if;

      return null;
   exception
      when Error_In_Regexp =>
         return null;
   end Files_Factory;

   ----------------------
   -- Auxiliary_Search --
   ----------------------

   procedure Auxiliary_Search
     (Context         : access Current_File_Context;
      Editor          : Source_Editor_Box;
      Kernel          : access Glide_Kernel.Kernel_Handle_Record'Class;
      Search_Backward : Boolean;
      Success         : out Boolean)
   is
      Lang   : Language_Access;
      Match  : Match_Result_Access;
      Line, Column : Natural;

   begin
      Success := False;

      Assert (Me, not Context.All_Occurrences,
              "All occurences not supported for current_file_context");

      --  If there are still some matches in the current file that we haven't
      --  returned, do it now (only the case when searching for all
      --  occurrences)

      if Context.Next_Matches_In_File /= null then
         if Search_Backward then
            Context.Last_Match_Returned := Context.Last_Match_Returned - 1;
         else
            Context.Last_Match_Returned := Context.Last_Match_Returned + 1;
         end if;

         --  Start from the beginning again if possible
         if Context.Last_Match_Returned <= 0
           or else Context.Last_Match_Returned
             > Context.Next_Matches_In_File'Last
           or else Context.Next_Matches_In_File (Context.Last_Match_Returned)
           = null
         then
            Context.Last_Match_Returned := Context.Next_Matches_In_File'First;
         end if;

         Match := Context.Next_Matches_In_File (Context.Last_Match_Returned);

         if Is_Valid_Location (Editor, Match.Line, Match.End_Column) then
            Context.Begin_Line := Match.Line;
            Context.Begin_Column := Match.Column;
            Context.End_Line := Match.Line;
            Context.End_Column := Match.End_Column;
            Success := True;

            --  ??? Match is not freed here ?
            return;

         else
            Free (Context.Next_Matches_In_File);
            return;
         end if;
      end if;

      --  Search either all occurrences at once, or only the next matching
      --  one. Note that when searching backward, we have to search from the
      --  beginning, since otherwise we don't know how to handle regular
      --  expressions and the search engine computed for Boyer-Moore is only
      --  for forward searches.

      Lang := Get_Language_From_File
        (Get_Language_Handler (Kernel), Get_Filename (Editor));
      Get_Cursor_Location (Editor, Line, Column);

      Match := Scan_Next
        (Context, Kernel,
         Editor         => Editor,
         Scope          => Context.Scope,
         Lang           => Lang,
         Current_Line   => Line,
         Current_Column => Column,
         Backward       => Search_Backward);

      if Match = null then
         return;
      end if;

      Context.Begin_Line := Match.Line;
      Context.Begin_Column := Match.Column;
      Context.End_Line := Match.Line;
      Context.End_Column := Match.End_Column;
      Success := True;

      Unchecked_Free (Match);

      return;
   end Auxiliary_Search;

   ------------
   -- Search --
   ------------

   function Search
     (Context         : access Current_File_Context;
      Kernel          : access Glide_Kernel.Kernel_Handle_Record'Class;
      Search_Backward : Boolean;
      Interactive     : Boolean) return Boolean

   is
      pragma Unreferenced (Interactive);

      Child   : constant MDI_Child := Find_Current_Editor (Kernel);
      Editor  : Source_Editor_Box;

      Success      : Boolean;

   begin
      if Child = null then
         return False;
      end if;

      Editor := Get_Source_Box_From_MDI (Child);
      Raise_Child (Child);
      Minimize_Child (Child, False);

      Auxiliary_Search (Context, Editor, Kernel, Search_Backward, Success);

      if Success then
         Set_Cursor_Location
           (Editor, Context.Begin_Line, Context.Begin_Column);
         Select_Region
           (Editor,
            Context.Begin_Line,
            Context.Begin_Column,
            Context.End_Line,
            Context.End_Column);
      end if;

      return Success;

   exception
      when E : others =>
         Trace (Me, "unexpected exception: " & Exception_Information (E));
         return False;
   end Search;

   -------------
   -- Replace --
   -------------

   function Replace
     (Context         : access Current_File_Context;
      Kernel          : access Glide_Kernel.Kernel_Handle_Record'Class;
      Replace_String  : String;
      Search_Backward : Boolean;
      Interactive     : Boolean) return Boolean
   is
      pragma Unreferenced (Interactive);
      Child   : constant MDI_Child := Find_Current_Editor (Kernel);
      Editor  : Source_Editor_Box;

      Success      : Boolean;
      Begin_Line   : Natural;
      Begin_Column : Natural;
      End_Line     : Natural;
      End_Column   : Natural;

   begin
      if Child = null then
         return False;
      end if;

      Editor := Get_Source_Box_From_MDI (Child);
      Raise_Child (Child);
      Minimize_Child (Child, False);

      --  Test whether there is currently a valid selection candidate
      --  for replacement.

      Get_Selection_Bounds (Editor, Begin_Line, Begin_Column,
                            End_Line, End_Column, Success);

      if Success
        and then Begin_Line = Context.Begin_Line
        and then Begin_Column = Context.Begin_Column
        and then End_Line = Context.End_Line
        and then End_Column = Context.End_Column
      then
         Replace_Slice
           (Editor,
            Begin_Line,
            Begin_Column,
            End_Line,
            End_Column,
            Replace_String);
      end if;

      --  Search for next replaceable entity.

      Auxiliary_Search (Context, Editor, Kernel, Search_Backward, Success);

      if Success then
         Set_Cursor_Location
           (Editor, Context.Begin_Line, Context.Begin_Column);
         Select_Region
           (Editor,
            Context.Begin_Line,
            Context.Begin_Column,
            Context.End_Line,
            Context.End_Column);
      else
         --  The search could not be made, invalidate the context
         --  in case it was the last search in the file.

         Context.End_Line := Context.Begin_Line;
         Context.End_Column := Context.Begin_Column;
      end if;

      return Success;

   exception
      when E : others =>
         Trace (Me, "unexpected exception: " & Exception_Information (E));
         return False;
   end Replace;

   ------------
   -- Search --
   ------------

   function Search
     (Context         : access Files_Project_Context;
      Kernel          : access Glide_Kernel.Kernel_Handle_Record'Class;
      Search_Backward : Boolean;
      Interactive     : Boolean) return Boolean
   is
      pragma Unreferenced (Search_Backward);
   begin
      --  If there are still some matches in the current file that we haven't
      --  returned, do it now.

      if Context.Next_Matches_In_File /= null then
         Context.Last_Match_Returned := Context.Last_Match_Returned + 1;
         if Context.Last_Match_Returned <= Context.Next_Matches_In_File'Last
           and then Context.Next_Matches_In_File (Context.Last_Match_Returned)
         /= null
         then
            Highlight_Result
              (Kernel, Context.Files (Context.Current_File - 1).all,
               Context.Next_Matches_In_File (Context.Last_Match_Returned).all,
               Interactive);

            return True;
         else
            Free (Context.Next_Matches_In_File);
         end if;
      end if;

      if Context.Files = null then
         return False;
      end if;

      --  ??? Should handle the case where the file has changed, when we are
      --  not searching for all occurrences.

      --  Loop until at least one match
      loop
         if Context.Current_File > Context.Files'Last then
            return False;
         end if;

         Context.Next_Matches_In_File := Scan_And_Store
           (Context, Kernel, Context.Files (Context.Current_File).all,
            Scope   => Context.Scope,
            Is_File => True);
         Context.Current_File := Context.Current_File + 1;

         exit when Context.Next_Matches_In_File /= null;
      end loop;

      Context.Last_Match_Returned := Context.Next_Matches_In_File'First;
      Highlight_Result
        (Kernel, Context.Files (Context.Current_File - 1).all,
         Context.Next_Matches_In_File (Context.Last_Match_Returned).all,
         Interactive);
      return True;
   end Search;

   -------------
   -- Replace --
   -------------

   function Replace
     (Context         : access Files_Project_Context;
      Kernel          : access Glide_Kernel.Kernel_Handle_Record'Class;
      Replace_String  : String;
      Search_Backward : Boolean;
      Interactive     : Boolean) return Boolean is
   begin
      if Context.Files = null
        or else Context.Current_File not in Context.Files'Range
        or else Context.Files (Context.Current_File) = null
      then
         return False;
      end if;

      if not Interactive
        and then not Is_Open (Kernel, Context.Files (Context.Current_File).all)
      then
         return False;

         --  ??? We do not replace strings in non-open buffers yet.
      else
         --  If the current location is valid, replace it.
         declare
            Start_Line   : Positive;
            Start_Column : Positive;
            End_Line     : Positive;
            End_Column   : Positive;
            Success      : Boolean;
            Editor       : Source_Editor_Box;
            Child        : constant MDI_Child := Find_Current_Editor (Kernel);
         begin
            if Child /= null then
               Editor := Get_Source_Box_From_MDI (Child);

               if Get_Filename (Editor)
                 = Context.Files (Context.Current_File - 1).all
               then
                  Get_Selection_Bounds
                    (Editor,
                     Start_Line, Start_Column, End_Line, End_Column,
                     Success);

                  if Success
                    and then Context.Next_Matches_In_File /= null
                    and then Context.Last_Match_Returned
                  in Context.Next_Matches_In_File'Range
                    and then Context.Next_Matches_In_File
                      (Context.Last_Match_Returned) /= null
                  then
                     declare
                        Match : constant Match_Result
                          := Context.Next_Matches_In_File
                            (Context.Last_Match_Returned).all;
                     begin
                        if Match.Line = Start_Line
                          and then Match.Column = Start_Column
                          and then Match.Line = End_Line
                          and then Match.End_Column = End_Column
                        then
                           Replace_Slice
                             (Editor,
                              Start_Line, Start_Column, End_Line, End_Column,
                              Replace_String);

                           return
                             Search
                               (Context,
                                Kernel,
                                Search_Backward,
                                Interactive);
                        end if;
                     end;
                  end if;
               end if;
            end if;
         end;
      end if;

      return False;
   end Replace;

   ------------
   -- Search --
   ------------

   function Search
     (Context         : access Files_Context;
      Kernel          : access Glide_Kernel.Kernel_Handle_Record'Class;
      Search_Backward : Boolean;
      Interactive     : Boolean) return Boolean
   is
      pragma Unreferenced (Search_Backward);

      use Directory_List;
      File_Name : String (1 .. Max_Path_Len);
      Last      : Natural;

   begin
      --  If there are still some matches in the current file that we haven't
      --  returned , do it now.

      if Context.Next_Matches_In_File /= null then
         Context.Last_Match_Returned := Context.Last_Match_Returned + 1;
         if Context.Last_Match_Returned <= Context.Next_Matches_In_File'Last
           and then Context.Next_Matches_In_File (Context.Last_Match_Returned)
           /= null
         then
            Highlight_Result
              (Kernel, Context.Current_File.all,
               Context.Next_Matches_In_File (Context.Last_Match_Returned).all,
               Interactive);
            return True;
         else
            Free (Context.Next_Matches_In_File);
         end if;
      end if;

      if Context.Directory = null then
         return False;
      end if;

      if Context.Dirs = Null_List then
         Prepend (Context.Dirs, new Dir_Data);
         Head (Context.Dirs).Name := new String'(Context.Directory.all);
         Open (Head (Context.Dirs).Dir, Context.Directory.all);
      end if;

      while Context.Next_Matches_In_File = null loop
         Read (Head (Context.Dirs).Dir, File_Name, Last);

         if Last = 0 then
            Next (Context.Dirs);

            if Context.Dirs = Null_List then
               return False;
            end if;

         else
            declare
               Full_Name : constant String :=
                 Head (Context.Dirs).Name.all & File_Name (1 .. Last);
            begin
               if Is_Directory (Full_Name) then
                  if Context.Recurse
                    and then File_Name (1 .. Last) /= "."
                    and then File_Name (1 .. Last) /= ".."
                    and then not Is_Symbolic_Link (File_Name (1 .. Last))
                  --  ??? Do not try to follow symbolic links for now,
                  --  so that we avoid infinite recursions.
                  then
                     Prepend (Context.Dirs, new Dir_Data);
                     Head (Context.Dirs).Name := new String'
                       (Name_As_Directory (Full_Name));
                     Open (Head (Context.Dirs).Dir, Full_Name);
                  end if;

               --  ??? Should check that we have a text file
               elsif Match (File_Name (1 .. Last), Context.Files_Pattern) then
                  Context.Next_Matches_In_File := Scan_And_Store
                    (Context, Kernel, Full_Name,
                     Scope   => Context.Scope,
                     Is_File => True);

                  if Context.Next_Matches_In_File /= null then
                     Free (Context.Current_File);
                     Context.Current_File := new String'(Full_Name);
                  end if;
               end if;
            end;
         end if;
      end loop;

      Context.Last_Match_Returned := Context.Next_Matches_In_File'First;
      Highlight_Result
        (Kernel, Context.Current_File.all,
         Context.Next_Matches_In_File (Context.Last_Match_Returned).all,
         Interactive);
      return True;

   exception
      when Directory_Error =>
         return False;
   end Search;

   -------------
   -- Replace --
   -------------

   function Replace
     (Context         : access Files_Context;
      Kernel          : access Glide_Kernel.Kernel_Handle_Record'Class;
      Replace_String  : String;
      Search_Backward : Boolean;
      Interactive     : Boolean) return Boolean is
   begin
      if Context.Current_File = null then
         return False;
      end if;

      if not Is_Open (Kernel, Context.Current_File.all) then
         return False;

         --  ??? We do not replace string in non-open buffers yet.
      else
         --  If the current location is valid, replace it.
         declare
            Start_Line   : Positive;
            Start_Column : Positive;
            End_Line     : Positive;
            End_Column   : Positive;
            Success      : Boolean;
            Editor       : Source_Editor_Box;
            Child        : constant MDI_Child := Find_Current_Editor (Kernel);
         begin
            if Child /= null then
               Editor := Get_Source_Box_From_MDI (Child);

               if Get_Filename (Editor) = Context.Current_File.all then
                  Get_Selection_Bounds
                    (Editor,
                     Start_Line, Start_Column, End_Line, End_Column,
                     Success);

                  if Success
                    and then Context.Next_Matches_In_File /= null
                    and then Context.Last_Match_Returned
                  in Context.Next_Matches_In_File'Range
                    and then Context.Next_Matches_In_File
                      (Context.Last_Match_Returned) /= null
                  then
                     declare
                        Match : constant Match_Result
                          := Context.Next_Matches_In_File
                            (Context.Last_Match_Returned).all;
                     begin
                        if Match.Line = Start_Line
                          and then Match.Column = Start_Column
                          and then Match.Line = End_Line
                          and then Match.End_Column = End_Column
                        then
                           Replace_Slice
                             (Editor,
                              Start_Line, Start_Column, End_Line, End_Column,
                              Replace_String);

                           return
                             Search
                               (Context,
                                Kernel,
                                Search_Backward,
                                Interactive);
                        end if;
                     end;
                  end if;
               end if;
            end if;
         end;
      end if;

      return False;
   end Replace;

   ----------
   -- Free --
   ----------

   procedure Free (D : in out Dir_Data_Access) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (Dir_Data, Dir_Data_Access);
   begin
      Close (D.Dir);
      Free (D.Name);
      Unchecked_Free (D);
   end Free;

   ----------------------------
   -- Initialize_Scope_Combo --
   ----------------------------

   procedure Initialize_Scope_Combo
     (Combo  : access Gtk_Combo_Record'Class;
      Kernel : access Kernel_Handle_Record'Class)
   is
      Scope_Combo_Items : Gtk.Enums.String_List.Glist;
   begin
      Set_Case_Sensitive (Combo, False);
      Gtk.Enums.String_List.Append (Scope_Combo_Items, -"Whole Text");
      Gtk.Enums.String_List.Append (Scope_Combo_Items, -"Comments Only");
      Gtk.Enums.String_List.Append (Scope_Combo_Items, -"Comments + Strings");
      Gtk.Enums.String_List.Append (Scope_Combo_Items, -"Strings Only");
      Gtk.Enums.String_List.Append (Scope_Combo_Items, -"All but Comments");
      Gtk.Combo.Set_Popdown_Strings (Combo, Scope_Combo_Items);
      Free_String_List (Scope_Combo_Items);

      Set_Editable (Get_Entry (Combo), False);
      Set_Max_Length (Get_Entry (Combo), 0);
      Set_Tip (Get_Tooltips (Kernel),
               Get_Entry (Combo),
               -"Restrict the scope of the search");

      Kernel_Callback.Connect
        (Get_Entry (Combo), "changed",
         Kernel_Callback.To_Marshaller (Reset_Search'Access),
         Kernel_Handle (Kernel));
   end Initialize_Scope_Combo;

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New
     (Selector : out Scope_Selector;
      Kernel   : access Kernel_Handle_Record'Class)
   is
      Box : Gtk_Box;
   begin
      Selector := new Scope_Selector_Record;
      Gtk.Frame.Initialize (Selector);
      Set_Label (Selector, -"Scope");

      Gtk_New_Hbox (Box, False, 0);
      Add (Selector, Box);

      Gtk_New (Selector.Combo);
      Pack_Start (Box, Selector.Combo, True, True, 2);
      Initialize_Scope_Combo (Selector.Combo, Kernel);
   end Gtk_New;

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New
     (Extra  : out Files_Extra_Scope;
      Kernel : access Glide_Kernel.Kernel_Handle_Record'Class)
   is
      Label : Gtk_Label;
   begin
      Extra := new Files_Extra_Scope_Record;
      Files_Extra_Info_Pkg.Initialize (Extra, Kernel);

      Gtk_New (Label, -"Scope:");
      Set_Alignment (Label, 0.0, 0.5);
      Attach (Extra.Files_Table, Label, 0, 1, 2, 3, Fill, 0);

      Gtk_New (Extra.Combo);
      Initialize_Scope_Combo (Extra.Combo, Kernel);
      Attach (Extra.Files_Table, Extra.Combo, 1, 3, 2, 3, Fill, 0);

      Kernel_Callback.Connect
        (Extra.Subdirs_Check, "toggled",
         Kernel_Callback.To_Marshaller (Reset_Search'Access),
         Kernel_Handle (Kernel));
      Kernel_Callback.Connect
        (Extra.Files_Entry, "changed",
         Kernel_Callback.To_Marshaller (Reset_Search'Access),
         Kernel_Handle (Kernel));
      Kernel_Callback.Connect
        (Extra.Directory_Entry, "changed",
         Kernel_Callback.To_Marshaller (Reset_Search'Access),
         Kernel_Handle (Kernel));
   end Gtk_New;

end Src_Contexts;
