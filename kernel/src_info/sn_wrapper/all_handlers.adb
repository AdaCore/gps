

------------------------
--  Fu_To_Cl_Handler  --
------------------------

procedure Fu_To_Cl_Handler (Ref : TO_Table)
is
   Class_Desc : CType_Description;
   Class_Def  : CL_Table;
   Success    : Boolean;
   Decl_Info  : E_Declaration_Info_List;
   Ref_Id     : constant String := Ref.Buffer
     (Ref.Referred_Symbol_Name.First .. Ref.Referred_Symbol_Name.Last);
begin

   Info ("Fu_To_Cl_Handler: " & Ref_Id);

   Find_Class
     (Type_Name      => Ref_Id,
      Desc           => Class_Desc,
      Class_Def      => Class_Def,
      Success        => Success);

   if not Success then
      Fail ("unable to find class " & Ref_Id);
      return;
   end if;

   if Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last) /=
         Class_Def.Buffer (Class_Def.File_Name.First ..
                                    Class_Def.File_Name.Last)
   then
      begin
         Decl_Info :=
           Find_Dependency_Declaration
             (File        => Global_LI_File,
              Symbol_Name => Class_Def.Buffer
                (Class_Def.Name.First .. Class_Def.Name.Last),
              Kind        => Record_Type,
              Location    => Class_Def.Start_Position,
              Filename    => Class_Def.Buffer
                (Class_Def.File_Name.First .. Class_Def.File_Name.Last));
      exception
         when Declaration_Not_Found =>
            Insert_Dependency_Declaration
              (Handler            => LI_Handler (Global_CPP_Handler),
               File               => Global_LI_File,
               List               => Global_LI_File_List,
               Symbol_Name        => Class_Def.Buffer
                 (Class_Def.Name.First .. Class_Def.Name.Last),
               Referred_Filename  => Class_Def.Buffer
                 (Class_Def.File_Name.First .. Class_Def.File_Name.Last),
               Source_Filename    => Ref.Buffer
                 (Ref.File_Name.First .. Ref.File_Name.Last),
               Location           => Class_Def.Start_Position,
               Kind               => Record_Type,
               Scope              => Global_Scope,
               Declaration_Info   => Decl_Info);
      end;
   else
      begin
         Decl_Info :=
           Find_Declaration
             (File        => Global_LI_File,
              Symbol_Name => Class_Def.Buffer
                (Class_Def.Name.First .. Class_Def.Name.Last),
              Kind        => Record_Type,
              Location    => Class_Def.Start_Position);
      exception
         when Declaration_Not_Found =>
            Insert_Declaration
              (Handler            => LI_Handler (Global_CPP_Handler),
               File               => Global_LI_File,
               List               => Global_LI_File_List,
               Symbol_Name        => Class_Def.Buffer
                 (Class_Def.Name.First .. Class_Def.Name.Last),
               Source_Filename    => Ref.Buffer
                 (Ref.File_Name.First .. Ref.File_Name.Last),
               Location           => Class_Def.Start_Position,
               Kind               => Record_Type,
               Scope              => Global_Scope,
               Declaration_Info   => Decl_Info);
      end;
   end if;
   Insert_Reference
     (File              => Global_LI_File,
      Declaration_Info  => Decl_Info,
      Source_Filename   => Ref.Buffer
        (Ref.File_Name.First .. Ref.File_Name.Last),
      Location          => Ref.Position,
      Kind              => Reference);
   Free (Class_Def);
   Free (Class_Desc);
end Fu_To_Cl_Handler;

------------------------
-- Fu_To_Con_Handler  --
------------------------

procedure Fu_To_Con_Handler (Ref : TO_Table) is
   Ref_Kind     : Reference_Kind;
   Decl_Info    : E_Declaration_Info_List;
   Var          : CON_Table;
   Desc         : CType_Description;
   Success      : Boolean;
   Scope        : E_Scope := Global_Scope;
   Attributes   : SN_Attributes;
begin
   Info ("Fu_To_Con_Handler: "
         & Ref.Buffer (Ref.Referred_Symbol_Name.First ..
               Ref.Referred_Symbol_Name.Last));

   --  we need declaration's location
   Var := Find (SN_Table (CON),
      Ref.Buffer (Ref.Referred_Symbol_Name.First ..
                  Ref.Referred_Symbol_Name.Last));

   --  Find declaration
   if Var.Buffer (Var.File_Name.First .. Var.File_Name.Last)
      = Get_LI_Filename (Global_LI_File) then
      begin
         Decl_Info := Find_Declaration
           (File                    => Global_LI_File,
            Symbol_Name             =>
               Ref.Buffer (Ref.Referred_Symbol_Name.First ..
                           Ref.Referred_Symbol_Name.Last),
            Location                => Var.Start_Position);
      exception
         when Declaration_Not_Found =>
            declare
               Sym : FIL_Table;
            begin
               Sym.Buffer         := Var.Buffer;
               Sym.Identifier     := Var.Name;
               Sym.Start_Position := Var.Start_Position;
               Sym.File_Name      := Var.File_Name;
               Sym_CON_Handler (Sym);
               Decl_Info := Find_Declaration
                 (File                    => Global_LI_File,
                  Symbol_Name             =>
                     Ref.Buffer (Ref.Referred_Symbol_Name.First ..
                                 Ref.Referred_Symbol_Name.Last),
                  Location                => Var.Start_Position);
            exception
               when Declaration_Not_Found =>
                  Fail ("Failed to create CON declaration");
                  Free (Var);
                  return;
            end;
      end;
   else -- another file
      begin -- Find dependency declaration
         Decl_Info := Find_Dependency_Declaration
           (File                    => Global_LI_File,
            Symbol_Name             =>
               Ref.Buffer (Ref.Referred_Symbol_Name.First ..
                           Ref.Referred_Symbol_Name.Last),
            Filename                =>
               Var.Buffer (Var.File_Name.First .. Var.File_Name.Last),
            Location                => Var.Start_Position);
      exception
         when Declaration_Not_Found => -- dep decl does not yet exist
            --  Collect information about the variable:
            --  type, scope, location of type declaration...
            Type_Name_To_Kind
              (Var.Buffer (Var.Declared_Type.First .. Var.Declared_Type.Last),
               Desc,
               Success);
            if not Success then -- unknown type
               Free (Var);
               return;
            end if;

            Attributes := SN_Attributes (Var.Attributes);

            if (Attributes and SN_STATIC) = SN_STATIC then
               Scope := Static_Local;
            end if;

            if Desc.Parent_Point = Invalid_Point then
               Insert_Dependency_Declaration
                 (Handler           => LI_Handler (Global_CPP_Handler),
                  File              => Global_LI_File,
                  List              => Global_LI_File_List,
                  Symbol_Name       =>
                     Var.Buffer (Var.Name.First .. Var.Name.Last),
                  Source_Filename   =>
                     Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location          => Var.Start_Position,
                  Kind              => Type_To_Object (Desc.Kind),
                  Scope             => Scope,
                  Referred_Filename =>
                     Var.Buffer (Var.File_Name.First .. Var.File_Name.Last),
                  Declaration_Info  => Decl_Info);
            else
               Insert_Dependency_Declaration
                 (Handler           => LI_Handler (Global_CPP_Handler),
                  File              => Global_LI_File,
                  List              => Global_LI_File_List,
                  Symbol_Name       =>
                     Var.Buffer (Var.Name.First .. Var.Name.Last),
                  Source_Filename   =>
                     Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location          => Var.Start_Position,
                  Kind              => Type_To_Object (Desc.Kind),
                  Scope             => Scope,
                  Referred_Filename =>
                     Var.Buffer (Var.File_Name.First .. Var.File_Name.Last),
                  Parent_Location   => Desc.Parent_Point,
                  Parent_Filename   => Desc.Parent_Filename.all,
                  Declaration_Info  => Decl_Info);
            end if;
            Free (Desc);
      end;
   end if;
   Free (Var);

   if Ref.Buffer (Ref.Access_Type.First) = 'r' then
      Ref_Kind := Reference;
   else
      Ref_Kind := Modification;
   end if;


   Insert_Reference
     (Declaration_Info        => Decl_Info,
      File                    => Global_LI_File,
      Source_Filename         =>
         Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
      Location                => Ref.Position,
      Kind                    => Ref_Kind);
exception
   when Not_Found  | DB_Error => -- ignore
      Fail ("unable to find constant " &
            Ref.Buffer (Ref.Referred_Symbol_Name.First ..
                        Ref.Referred_Symbol_Name.Last));
end Fu_To_Con_Handler;


------------------------
--  Fu_To_E_Handler  --
------------------------

procedure Fu_To_E_Handler (Ref : TO_Table)
is
   Ref_Id : constant String := Ref.Buffer
     (Ref.Referred_Symbol_Name.First .. Ref.Referred_Symbol_Name.Last);
   Enum_Desc : CType_Description;
   Enum_Def  : E_Table;
   Success    : Boolean;
   Decl_Info  : E_Declaration_Info_List;
begin

   Info ("Fu_To_E_Handler: " & Ref_Id);

   Find_Enum
     (Type_Name      => Ref_Id,
      Desc           => Enum_Desc,
      Enum_Def       => Enum_Def,
      Success        => Success);

   if not Success then
      Fail ("unable to find enum " & Ref_Id);
      return;
   end if;

   if Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last) /=
         Enum_Def.Buffer (Enum_Def.File_Name.First ..
                                    Enum_Def.File_Name.Last)
   then
      begin
         Decl_Info :=
           Find_Dependency_Declaration
             (File        => Global_LI_File,
              Symbol_Name => Enum_Def.Buffer
                (Enum_Def.Name.First .. Enum_Def.Name.Last),
              Kind        => Enumeration_Type,
              Location    => Enum_Def.Start_Position,
              Filename    => Enum_Def.Buffer
                (Enum_Def.File_Name.First .. Enum_Def.File_Name.Last));
      exception
         when Declaration_Not_Found =>
            Insert_Dependency_Declaration
              (Handler            => LI_Handler (Global_CPP_Handler),
               File               => Global_LI_File,
               List               => Global_LI_File_List,
               Symbol_Name        => Enum_Def.Buffer
                 (Enum_Def.Name.First .. Enum_Def.Name.Last),
               Referred_Filename  => Enum_Def.Buffer
                 (Enum_Def.File_Name.First .. Enum_Def.File_Name.Last),
               Source_Filename    => Ref.Buffer
                 (Ref.File_Name.First .. Ref.File_Name.Last),
               Location           => Enum_Def.Start_Position,
               Kind               => Enumeration_Type,
               Scope              => Global_Scope,
               Declaration_Info   => Decl_Info);
      end;
   else
      begin
         Decl_Info :=
           Find_Declaration
             (File        => Global_LI_File,
              Symbol_Name => Enum_Def.Buffer
                (Enum_Def.Name.First .. Enum_Def.Name.Last),
              Kind        => Enumeration_Type,
              Location    => Enum_Def.Start_Position);
      exception
         when Declaration_Not_Found =>
            Insert_Declaration
              (Handler            => LI_Handler (Global_CPP_Handler),
               File               => Global_LI_File,
               List               => Global_LI_File_List,
               Symbol_Name        => Enum_Def.Buffer
                 (Enum_Def.Name.First .. Enum_Def.Name.Last),
               Source_Filename    => Ref.Buffer
                 (Ref.File_Name.First .. Ref.File_Name.Last),
               Location           => Enum_Def.Start_Position,
               Kind               => Enumeration_Type,
               Scope              => Global_Scope,
               Declaration_Info   => Decl_Info);
      end;
   end if;
   Insert_Reference
     (File              => Global_LI_File,
      Declaration_Info  => Decl_Info,
      Source_Filename   => Ref.Buffer
        (Ref.File_Name.First .. Ref.File_Name.Last),
      Location          => Ref.Position,
      Kind              => Reference);
   Free (Enum_Def);
   Free (Enum_Desc);
end Fu_To_E_Handler;


------------------------
--  Fu_To_Ec_Handler  --
------------------------

procedure Fu_To_Ec_Handler (Ref : TO_Table) is
   Decl_Info    : E_Declaration_Info_List;
   Enum_Const   : EC_Table;
   Ref_Id       : constant String := Ref.Buffer
     (Ref.Referred_Symbol_Name.First .. Ref.Referred_Symbol_Name.Last);
begin

   Info ("Fu_To_EC_Handler: " & Ref_Id);

   Enum_Const := Find (SN_Table (EC), Ref_Id);

   --  Find declaration
   if Enum_Const.Buffer
      (Enum_Const.File_Name.First .. Enum_Const.File_Name.Last)
      = Get_LI_Filename (Global_LI_File) then
      begin
         Decl_Info := Find_Declaration
           (File                    => Global_LI_File,
            Symbol_Name             => Ref_Id,
            Location                => Enum_Const.Start_Position);
      exception
         when Declaration_Not_Found =>
            Insert_Declaration
              (Handler           => LI_Handler (Global_CPP_Handler),
               File              => Global_LI_File,
               List              => Global_LI_File_List,
               Symbol_Name       => Ref_Id,
               Source_Filename   =>
                  Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
               Location          => Enum_Const.Start_Position,
               Kind              => Enumeration_Literal,
               Scope             => Global_Scope,
               Declaration_Info  => Decl_Info);
      end;
   else -- another file
      begin -- Find dependency declaration
         Decl_Info := Find_Dependency_Declaration
           (File                    => Global_LI_File,
            Symbol_Name             => Ref_Id,
            Filename                =>
               Enum_Const.Buffer (Enum_Const.File_Name.First ..
                                  Enum_Const.File_Name.Last),
            Location                => Enum_Const.Start_Position);
      exception
         when Declaration_Not_Found => -- dep decl does not yet exist
            Insert_Dependency_Declaration
              (Handler           => LI_Handler (Global_CPP_Handler),
               File              => Global_LI_File,
               List              => Global_LI_File_List,
               Symbol_Name       => Ref_Id,
               Source_Filename   =>
                  Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
               Location          => Enum_Const.Start_Position,
               Kind              => Enumeration_Literal,
               Scope             => Global_Scope,
               Referred_Filename =>
                  Enum_Const.Buffer (Enum_Const.File_Name.First ..
                                     Enum_Const.File_Name.Last),
               Declaration_Info  => Decl_Info);
      end;
   end if;
   Free (Enum_Const);

   Insert_Reference
     (Declaration_Info        => Decl_Info,
      File                    => Global_LI_File,
      Source_Filename         =>
         Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
      Location                => Ref.Position,
      Kind                    => Reference);

exception

   when DB_Error | Not_Found =>
      Fail ("unable to find enumeration constant " & Ref_Id);

end Fu_To_Ec_Handler;



------------------------
--  Fu_To_Fu_Handler  --
------------------------

procedure Fu_To_Fu_Handler (Ref : TO_Table) is
   P              : Pair_Ptr;
   Fn             : FU_Table;
   Fn_Tmp         : FU_Table;
   Decl_Info      : E_Declaration_Info_List;
   Overloaded     : Boolean := False;
   Forward_Declared : Boolean := False;
   No_Body        : Boolean := True;
   Kind           : E_Kind;
   FDecl          : FD_Table;
   FDecl_Tmp      : FD_Table;
   Ref_Id         : constant String := Ref.Buffer
     (Ref.Referred_Symbol_Name.First .. Ref.Referred_Symbol_Name.Last);
   Buffer   : SN.String_Access;
   Filename       : Segment;
   Return_Type    : Segment;
   Start_Position : Point;
begin

   Info ("Fu_To_Fu_Handler: " & Ref_Id);

   if Is_Open (SN_Table (FD)) then
      Set_Cursor (SN_Table (FD), By_Key, Ref_Id, False);

      loop
         P := Get_Pair (SN_Table (FD), Next_By_Key);
         exit when P = null;
         FDecl_Tmp := Parse_Pair (P.all);
         Free (P);
         if not Forward_Declared then
            FDecl := FDecl_Tmp;
            Forward_Declared := True;
         else
            Overloaded := not Cmp_Arg_Types -- skip multiple fwd decls
               (FDecl.Buffer,
                FDecl_Tmp.Buffer,
                FDecl.Arg_Types,
                FDecl_Tmp.Arg_Types);
            Free (FDecl_Tmp);
            exit when Overloaded;
         end if;
      end loop;
   end if;

   if not Overloaded then
      --  Forward declarations may be overloaded by inline implementations
      --  this is what we check here. If no forward declaration was found
      --  above we search for a suitable function body
      Set_Cursor (SN_Table (FU), By_Key, Ref_Id, False);

      loop
         P := Get_Pair (SN_Table (FU), Next_By_Key);
         exit when P = null;
         Fn_Tmp := Parse_Pair (P.all);
         Free (P);
         if not Forward_Declared and No_Body then
            --  No forward decls, but we found the first function
            --  with the same name
            Fn      := Fn_Tmp;
            No_Body := False;
         elsif not Forward_Declared and not No_Body then
            --  No forward decls and we found one more function body
            --  with the same name
            Overloaded := True;
            Free (Fn_Tmp);
         elsif Forward_Declared and No_Body then
            --  We have found some forward declaration, but no body
            --  is yet found. Do we have overloading here?
            Overloaded := not Cmp_Arg_Types
               (Fn_Tmp.Buffer,
                FDecl.Buffer,
                Fn_Tmp.Arg_Types,
                FDecl.Arg_Types);
            if not Overloaded then -- we found the body!
               No_Body := False;
               Fn      := Fn_Tmp;
            else
               Free (Fn_Tmp); -- it's not our body, but it's overloading
            end if;
         else -- Forward_Declared and not No_Body
            --  We have found forward declaration and corresponding body
            --  all other bodies should be overloading functions
            Overloaded := True;
            Free (Fn_Tmp);
         end if;
         exit when Overloaded;
      end loop;
   end if;

   if not Forward_Declared and No_Body then
      Fail ("Can't find either forward declaration or body for " & Ref_Id);
      return;
   end if;

   if not Overloaded then
      pragma Assert (Forward_Declared or not No_Body, "Hey, what's up?");
      if No_Body then
         Buffer   := FDecl.Buffer;
         Filename       := FDecl.File_Name;
         Start_Position := FDecl.Start_Position;
         Return_Type    := FDecl.Return_Type;
      else
         Buffer   := Fn.Buffer;
         Filename       := Fn.File_Name;
         Start_Position := Fn.Start_Position;
         Return_Type    := Fn.Return_Type;
      end if;

      if Buffer (Return_Type.First .. Return_Type.Last) = "void" then
         Kind := Non_Generic_Function_Or_Operator;
      else
         Kind := Non_Generic_Procedure;
      end if;
      --  If procedure
      --    defined in the current file => add reference
      --    defined in another file => add dep decl and reference it
      if Buffer (Filename.First .. Filename.Last)
            = Get_LI_Filename (Global_LI_File) then
         begin
            --  this is a function defined in the current file
            --  it may be either forward declared or implemented
            --  right away
            if Forward_Declared then
               Decl_Info := Find_First_Forward_Declaration
                 (FDecl.Buffer,
                  FDecl.Name,
                  FDecl.File_Name,
                  FDecl.Return_Type,
                  FDecl.Arg_Types);
               if Decl_Info = null then
                  raise Declaration_Not_Found;
               end if;
            else -- when only body is available
               Decl_Info := Find_Declaration
                 (File        => Global_LI_File,
                  Symbol_Name => Fn.Buffer (Fn.Name.First .. Fn.Name.Last),
                  Location    => Fn.Start_Position);
            end if;
         exception
            when Declaration_Not_Found =>
               --  function is in the current file, but used before
               --  declaration. Create forward declaration
               Insert_Declaration
                 (Handler            => LI_Handler (Global_CPP_Handler),
                  File               => Global_LI_File,
                  List               => Global_LI_File_List,
                  Symbol_Name        => Ref_Id,
                  Source_Filename    => Ref.Buffer
                     (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location           => Ref.Position,
                  Kind               => Kind,
                  Scope              => Global_Scope,
                  Declaration_Info   => Decl_Info);
         end;
      else
         begin
            --  this function is defined somewhere else...
            Decl_Info := Find_Dependency_Declaration
              (File                 => Global_LI_File,
               Symbol_Name          => Ref_Id,
               Filename             => Buffer
                 (Filename.First .. Filename.Last),
               Location             => Start_Position);
         exception
            when Declaration_Not_Found => -- insert dep decl
               Insert_Dependency_Declaration
                 (Handler            => LI_Handler (Global_CPP_Handler),
                  File               => Global_LI_File,
                  List               => Global_LI_File_List,
                  Symbol_Name        => Ref_Id,
                  Source_Filename    =>
                     Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location           => Start_Position,
                  Kind               => Kind,
                  Scope              => Global_Scope,
                  Referred_Filename  => Buffer
                    (Filename.First .. Filename.Last),
                  Declaration_Info   => Decl_Info);
         end;
      end if;
   else -- overloaded entity
      --  have we already declared it?
      begin
         Decl_Info := Find_Declaration
           (File        => Global_LI_File,
            Symbol_Name => Ref_Id,
            Kind        => Overloaded_Entity);
      exception
         when Declaration_Not_Found =>
            Decl_Info := new E_Declaration_Info_Node'
              (Value =>
                 (Declaration => No_Declaration,
                  References => null),
               Next => Global_LI_File.LI.Body_Info.Declarations);
            Decl_Info.Value.Declaration.Name := new String'(Ref_Id);
            Decl_Info.Value.Declaration.Kind := Overloaded_Entity;
            Global_LI_File.LI.Body_Info.Declarations := Decl_Info;
      end;
   end if;

   if Forward_Declared then
      Free (FDecl);
   end if;

   if not No_Body then
      Free (Fn);
   end if;

   Insert_Reference
     (Decl_Info,
      Global_LI_File,
      Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
      Ref.Position,
      Reference);
exception
   when Not_Found  | DB_Error => -- ignore
      Fail ("unable to find function " & Ref_Id);
   return;
end Fu_To_Fu_Handler;


------------------------
--  Fu_To_Gv_Handler  --
------------------------

procedure Fu_To_Gv_Handler (Ref : TO_Table) is
   Ref_Kind     : Reference_Kind;
   Decl_Info    : E_Declaration_Info_List;
   Var          : GV_Table;
   Desc         : CType_Description;
   Success      : Boolean;
   Scope        : E_Scope := Global_Scope;
   Attributes   : SN_Attributes;
   Ref_Id       : constant String := Ref.Buffer
     (Ref.Referred_Symbol_Name.First .. Ref.Referred_Symbol_Name.Last);
begin
   Info ("Fu_To_GV_Handler: " & Ref_Id);

   --  we need declaration's location
   Var := Find (SN_Table (GV), Ref_Id);

   --  Find declaration
   if Var.Buffer (Var.File_Name.First .. Var.File_Name.Last)
      = Get_LI_Filename (Global_LI_File) then
      begin
         Decl_Info := Find_Declaration
           (File                    => Global_LI_File,
            Symbol_Name             => Ref_Id,
            Location                => Var.Start_Position);
      exception
         when Declaration_Not_Found =>
            declare
               Sym : FIL_Table;
            begin
               Sym.Buffer         := Var.Buffer;
               Sym.Identifier     := Var.Name;
               Sym.Start_Position := Var.Start_Position;
               Sym.File_Name      := Var.File_Name;
               Sym_GV_Handler (Sym);
               Decl_Info := Find_Declaration
                 (File                    => Global_LI_File,
                  Symbol_Name             => Ref_Id,
                  Location                => Var.Start_Position);
            exception
               when Declaration_Not_Found =>
                  Fail ("unable to create declaration for global variable "
                        & Ref_Id);
                  Free (Var);
                  return;
            end;
      end;
   else -- another file
      begin -- Find dependency declaration
         Decl_Info := Find_Dependency_Declaration
           (File                    => Global_LI_File,
            Symbol_Name             => Ref_Id,
            Filename                =>
               Var.Buffer (Var.File_Name.First .. Var.File_Name.Last),
            Location                => Var.Start_Position);
      exception
         when Declaration_Not_Found => -- dep decl does not yet exist
            --  Collect information about the variable:
            --  type, scope, location of type declaration...
            Type_Name_To_Kind
              (Var.Buffer (Var.Value_Type.First .. Var.Value_Type.Last),
               Desc,
               Success);
            if not Success then -- unknown type
               Free (Var);
               return;
            end if;

            Attributes := SN_Attributes (Var.Attributes);

            if (Attributes and SN_STATIC) = SN_STATIC then
               Scope := Static_Local;
            end if;

            if Desc.Parent_Point = Invalid_Point then
               Insert_Dependency_Declaration
                 (Handler           => LI_Handler (Global_CPP_Handler),
                  File              => Global_LI_File,
                  List              => Global_LI_File_List,
                  Symbol_Name       =>
                     Var.Buffer (Var.Name.First .. Var.Name.Last),
                  Source_Filename   =>
                     Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location          => Var.Start_Position,
                  Kind              => Type_To_Object (Desc.Kind),
                  Scope             => Scope,
                  Referred_Filename =>
                     Var.Buffer (Var.File_Name.First .. Var.File_Name.Last),
                  Declaration_Info  => Decl_Info);
            else
               Insert_Dependency_Declaration
                 (Handler           => LI_Handler (Global_CPP_Handler),
                  File              => Global_LI_File,
                  List              => Global_LI_File_List,
                  Symbol_Name       =>
                     Var.Buffer (Var.Name.First .. Var.Name.Last),
                  Source_Filename   =>
                     Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location          => Var.Start_Position,
                  Kind              => Type_To_Object (Desc.Kind),
                  Scope             => Scope,
                  Referred_Filename =>
                     Var.Buffer (Var.File_Name.First .. Var.File_Name.Last),
                  Parent_Location   => Desc.Parent_Point,
                  Parent_Filename   => Desc.Parent_Filename.all,
                  Declaration_Info  => Decl_Info);
            end if;
            Free (Desc);
      end;
   end if;
   Free (Var);

   if Ref.Buffer (Ref.Access_Type.First) = 'r' then
      Ref_Kind := Reference;
   else
      Ref_Kind := Modification;
   end if;


   Insert_Reference
     (Declaration_Info        => Decl_Info,
      File                    => Global_LI_File,
      Source_Filename         =>
         Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
      Location                => Ref.Position,
      Kind                    => Ref_Kind);
exception
   when Not_Found  | DB_Error => -- ignore
      Fail ("unable to find global variable " & Ref_Id);
end Fu_To_Gv_Handler;


------------------------
--  Fu_To_Ma_Handler  --
------------------------

procedure Fu_To_Ma_Handler (Ref : TO_Table) is
   Macro  : MA_Table;
   Ref_Id : constant String := Ref.Buffer
     (Ref.Referred_Symbol_Name.First .. Ref.Referred_Symbol_Name.Last);
   Decl_Info : E_Declaration_Info_List;
begin
   if not Is_Open (SN_Table (MA)) then
      --  .ma table does not exist
      return;
   end if;

   Info ("Fu_To_Ma: " & Ref_Id);

   Macro := Find (SN_Table (MA), Ref_Id);

   if Macro.Buffer (Macro.File_Name.First .. Macro.File_Name.Last)
     = Get_LI_Filename (Global_LI_File)
   then
      begin
         --  look for declaration in current file
         Decl_Info := Find_Declaration
           (File        => Global_LI_File,
            Symbol_Name => Ref_Id,
            Location    => Macro.Start_Position);

      exception
         when Declaration_Not_Found =>
            Insert_Declaration
              (Handler            => LI_Handler (Global_CPP_Handler),
               File               => Global_LI_File,
               List               => Global_LI_File_List,
               Symbol_Name        => Ref_Id,
               Source_Filename    => Ref.Buffer
                 (Ref.File_Name.First .. Ref.File_Name.Last),
               Location           => Macro.Start_Position,
               Kind               => Unresolved_Entity,
               Scope              => Global_Scope,
               Declaration_Info   => Decl_Info);
      end;
   else
      --  look for dependency declaration
      begin
         Decl_Info := Find_Dependency_Declaration
           (File                 => Global_LI_File,
            Symbol_Name          => Ref_Id,
            Filename             => Macro.Buffer
              (Macro.File_Name.First .. Macro.File_Name.Last),
            Location             => Macro.Start_Position);
      exception
         when Declaration_Not_Found => -- dep decl does not yet exist
            Insert_Dependency_Declaration
              (Handler           => LI_Handler (Global_CPP_Handler),
               File              => Global_LI_File,
               List              => Global_LI_File_List,
               Symbol_Name       => Ref_Id,
               Source_Filename   => Ref.Buffer
                 (Ref.File_Name.First .. Ref.File_Name.Last),
               Location          => Macro.Start_Position,
               Kind              => Unresolved_Entity,
               Scope             => Global_Scope,
               Referred_Filename => Macro.Buffer
                 (Macro.File_Name.First .. Macro.File_Name.Last),
               Declaration_Info  => Decl_Info);
      end;
   end if;

   Insert_Reference
     (Declaration_Info     => Decl_Info,
      File                 => Global_LI_File,
      Source_Filename      =>
        Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
      Location             => Ref.Position,
      Kind                 => Reference);

   Free (Macro);

exception
   when DB_Error | Not_Found =>
      Fail ("unable to find macro " & Ref_Id);

end Fu_To_Ma_Handler;



------------------------
--  Fu_To_Mi_Handler  --
------------------------

procedure Fu_To_Mi_Handler (Ref : TO_Table) is
   P             : Pair_Ptr;
   Fn            : MI_Table;
   MDecl         : MD_Table;
   MDecl_Tmp     : MD_Table;
   Decl_Info     : E_Declaration_Info_List;
   Overloaded    : Boolean := False;
   Init          : Boolean := True;
   Pure_Virtual  : Boolean := False;
   Kind          : E_Kind;
   IsTemplate    : Boolean := False;
   Ref_Id        : constant String := Ref.Buffer
     (Ref.Referred_Symbol_Name.First .. Ref.Referred_Symbol_Name.Last);
   Ref_Class     : constant String := Ref.Buffer
     (Ref.Referred_Class.First .. Ref.Referred_Class.Last);
   Attributes    : SN_Attributes;
   Filename_Buf  : SN.String_Access;
   Filename      : Segment;
   Start_Position : Point;

   function Find_Method (Fn : MI_Table; MD_Tab : MD_Table)
      return E_Declaration_Info_List;
   --  searches for forward declaration. if no fwd decl found, searches for
   --  implementation. If nothing found throws Declaration_Not_Found

   function Find_Method (Fn : MI_Table; MD_Tab : MD_Table)
      return E_Declaration_Info_List is
      Decl_Info    : E_Declaration_Info_List;
   begin
      Decl_Info := Find_First_Forward_Declaration
        (MD_Tab.Buffer,
         MD_Tab.Class,
         MD_Tab.Name,
         MD_Tab.File_Name,
         MD_Tab.Return_Type,
         MD_Tab.Arg_Types);
      if Decl_Info = null then
         raise Declaration_Not_Found;
      end if;
      return Decl_Info;
   exception
      when Declaration_Not_Found =>
         return Find_Declaration
           (File        => Global_LI_File,
            Symbol_Name => Fn.Buffer (Fn.Name.First .. Fn.Name.Last),
            Class_Name  => Fn.Buffer (Fn.Class.First .. Fn.Class.Last),
            Location    => Fn.Start_Position);
   end Find_Method;

begin

   Info ("Fu_To_Mi_Handler: " & Ref_Id);

   Set_Cursor
     (SN_Table (MD),
      By_Key,
      Ref_Class & Field_Sep & Ref_Id & Field_Sep,
      False);

   loop
      P := Get_Pair (SN_Table (MD), Next_By_Key);
      exit when P = null;
      MDecl_Tmp := Parse_Pair (P.all);
      Free (P);
      if Init then
         Init  := False;
         MDecl := MDecl_Tmp;
      else
         Overloaded := not Cmp_Arg_Types -- skip multiple fws decls
           (MDecl_Tmp.Buffer,
            MDecl.Buffer,
            MDecl_Tmp.Arg_Types,
            MDecl.Arg_Types);
         Free (MDecl_Tmp);
         exit when Overloaded;
      end if;
   end loop;

   if Init then -- declaration for the referred method not found
      --  ??? We should handle this situation in a special way:
      Fail ("unable to find method " & Ref_Class & "::" & Ref_Id);
      return;
   end if;

   --  Once we have found the declaration(s) we may try to look up
   --  implementation as well
   if not Overloaded then
      Set_Cursor
        (SN_Table (MI),
         By_Key,
         Ref_Class & Field_Sep & Ref_Id & Field_Sep,
         False);

      Init := True;
      loop
         P := Get_Pair (SN_Table (MI), Next_By_Key);
         exit when P = null;
         Fn := Parse_Pair (P.all);
         Free (P);
         Init := False;
         exit when Cmp_Arg_Types
           (MDecl.Buffer,
            Fn.Buffer,
            MDecl.Arg_Types,
            Fn.Arg_Types);
         Init := True;
         Free (Fn);
      end loop;

      if Init then -- implementation for the referred method not found
         --  this must be a pure virtual method
         Attributes := SN_Attributes (MDecl.Attributes);
         if (Attributes and SN_PUREVIRTUAL) /= SN_PUREVIRTUAL then
            Fail ("failed to locate method implementation, but it is not"
               & " an abstract one: " & Ref_Class & "::" & Ref_Id);
            Free (MDecl);
            return;
         end if;
         Pure_Virtual := True;
      end if;

      --  If method
      --    defined in the current file => add reference
      --    defined in another file => add dep decl and reference it
      declare
         Class_Def    : CL_Table;
      begin -- check if this class is template
         Class_Def := Find (SN_Table (CL), Ref_Class);
         IsTemplate := Class_Def.Template_Parameters.First
            < Class_Def.Template_Parameters.Last;
         Free (Class_Def);
      exception
         when DB_Error | Not_Found =>
            null;
      end;

      if Pure_Virtual then
         Filename_Buf   := MDecl.Buffer;
         Filename       := MDecl.File_Name;
         Start_Position := MDecl.Start_Position;
      else
         Filename_Buf   := Fn.Buffer;
         Filename       := Fn.File_Name;
         Start_Position := Fn.Start_Position;
      end if;

      if MDecl.Buffer (MDecl.Return_Type.First .. MDecl.Return_Type.Last)
            = "void" then
         if IsTemplate then
            Kind := Generic_Function_Or_Operator;
         else
            Kind := Non_Generic_Function_Or_Operator;
         end if;
      else
         if IsTemplate then
            Kind := Generic_Procedure;
         else
            Kind := Non_Generic_Procedure;
         end if;
      end if;
      if Filename_Buf (Filename.First .. Filename.Last)
            = Get_LI_Filename (Global_LI_File) then
         begin
            --  this is a method defined in the current file
            --  it may be either forward declared or implemented
            --  right away
            if Pure_Virtual then
               Decl_Info := Find_First_Forward_Declaration
                 (MDecl.Buffer,
                  MDecl.Class,
                  MDecl.Name,
                  MDecl.File_Name,
                  MDecl.Return_Type,
                  MDecl.Arg_Types);
               if Decl_Info = null then
                  raise Declaration_Not_Found;
               end if;
            else
               Decl_Info := Find_Method (Fn, MDecl);
            end if;
         exception
            when Declaration_Not_Found =>
               --  method is in the current file, but used before
               --  declaration. Create forward declaration
               Insert_Declaration
                 (Handler            => LI_Handler (Global_CPP_Handler),
                  File               => Global_LI_File,
                  List               => Global_LI_File_List,
                  Symbol_Name        => Ref_Id,
                  Source_Filename    => Ref.Buffer
                    (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location           => Ref.Position,
                  Kind               => Kind,
                  Scope              => Global_Scope,
                  Declaration_Info   => Decl_Info);
         end;
      else
         begin
            --  this method is defined somewhere else...
            Decl_Info := Find_Dependency_Declaration
              (File                 => Global_LI_File,
               Symbol_Name          => Ref_Id,
               Class_Name           => Ref_Class,
               Filename             => Filename_Buf
                 (Filename.First .. Filename.Last),
               Location             => Start_Position);
         exception
            when Declaration_Not_Found => -- insert dep decl
               Insert_Dependency_Declaration
                 (Handler            => LI_Handler (Global_CPP_Handler),
                  File               => Global_LI_File,
                  List               => Global_LI_File_List,
                  Symbol_Name        => Ref_Id,
                  Source_Filename    => Ref.Buffer
                     (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location           => Start_Position,
                  Kind               => Kind,
                  Scope              => Global_Scope,
                  Referred_Filename  => Filename_Buf
                     (Filename.First .. Filename.Last),
                  Declaration_Info   => Decl_Info);
         end;
      end if;

      if not Pure_Virtual then
         Free (Fn);
      end if;
   else -- overloaded entity
      --  have we already declared it?
      declare
         Class_Def : CL_Table;
      begin
         Class_Def := Find (SN_Table (CL), Ref_Class);
         --  ??? what to do when several classes with one name are available
         --  what about unions?

         Decl_Info := Find_Declaration
           (File        => Global_LI_File,
            Symbol_Name => Ref_Id,
            Class_Name  => Ref_Class,
            Kind        => Overloaded_Entity,
            Location    => Class_Def.Start_Position);
         Free (Class_Def);
      exception
         when DB_Error | Not_Found =>
            Fail ("Failed to lookup class " & Ref_Class
               & " for method " & Ref_Id);
            Free (MDecl);
            return;
         when Declaration_Not_Found =>
            Decl_Info := new E_Declaration_Info_Node'
              (Value =>
                 (Declaration => No_Declaration,
                  References => null),
               Next => Global_LI_File.LI.Body_Info.Declarations);
            Decl_Info.Value.Declaration.Name := new String'(Ref_Id);
            Decl_Info.Value.Declaration.Kind := Overloaded_Entity;
            Decl_Info.Value.Declaration.Location.Line :=
               Class_Def.Start_Position.Line;
            Decl_Info.Value.Declaration.Location.File :=
               (LI              => Global_LI_File,
                Part            => Unit_Body,
                Source_Filename =>
                   new String'(Get_LI_Filename (Global_LI_File)));
            Decl_Info.Value.Declaration.Location.Column :=
               Class_Def.Start_Position.Column;
            Global_LI_File.LI.Body_Info.Declarations := Decl_Info;
            Free (Class_Def);
      end;
   end if;
   Free (MDecl);

   Insert_Reference
     (Decl_Info,
      Global_LI_File,
      Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
      Ref.Position,
      Reference);
exception
   when Not_Found  | DB_Error => -- ignore
      Fail ("unable to find method " & Ref_Class & "::" & Ref_Id);
      return;
end Fu_To_Mi_Handler;


------------------------
--  Fu_To_T_Handler  --
------------------------

procedure Fu_To_T_Handler (Ref : TO_Table) is
   Typedef   : T_Table;
   Ref_Id    : constant String := Ref.Buffer
     (Ref.Referred_Symbol_Name.First .. Ref.Referred_Symbol_Name.Last);
   Decl_Info : E_Declaration_Info_List;
   Desc      : CType_Description;
   Success   : Boolean := False;
begin
   if not Is_Open (SN_Table (T)) then
      --  .t table does not exist
      return;
   end if;

   Info ("Fu_To_T: " & Ref_Id);

   Typedef := Find (SN_Table (T), Ref_Id);

   if Typedef.Buffer (Typedef.File_Name.First .. Typedef.File_Name.Last)
     = Get_LI_Filename (Global_LI_File)
   then
      begin
         --  look for declaration in current file
         Decl_Info := Find_Declaration
           (File        => Global_LI_File,
            Symbol_Name => Ref_Id,
            Location    => Typedef.Start_Position);

      exception
         when Declaration_Not_Found =>
            --  Declaration for type is not created yet
            Original_Type (Ref_Id, Desc, Success);

            if not Success then
               Fail ("unable to find type for typedef " & Ref_Id);
               Free (Desc);
               Free (Typedef);
               return;
            end if;

            if Desc.Ancestor_Point = Invalid_Point then
               --  unknown parent
               Insert_Declaration
                 (Handler           => LI_Handler (Global_CPP_Handler),
                  File              => Global_LI_File,
                  List              => Global_LI_File_List,
                  Symbol_Name       => Ref_Id,
                  Source_Filename   => Ref.Buffer
                    (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location          => Typedef.Start_Position,
                  Kind              => Desc.Kind,
                  Scope             => Global_Scope,
                  Declaration_Info  => Decl_Info);
            elsif Desc.Ancestor_Point = Predefined_Point then
               --  typedef for builin type
               Insert_Declaration
                 (Handler           => LI_Handler (Global_CPP_Handler),
                  File              => Global_LI_File,
                  List              => Global_LI_File_List,
                  Symbol_Name       => Ref_Id,
                  Source_Filename   => Ref.Buffer
                    (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location          => Typedef.Start_Position,
                  Parent_Location   => Predefined_Point,
                  Kind              => Desc.Kind,
                  Scope             => Global_Scope,
                  Declaration_Info  => Decl_Info);
            else
               --  parent type found
               Insert_Declaration
                 (Handler           => LI_Handler (Global_CPP_Handler),
                  File              => Global_LI_File,
                  List              => Global_LI_File_List,
                  Symbol_Name       => Ref_Id,
                  Source_Filename   => Ref.Buffer
                    (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location          => Typedef.Start_Position,
                  Parent_Location   => Desc.Ancestor_Point,
                  Parent_Filename   => Desc.Ancestor_Filename.all,
                  Kind              => Desc.Kind,
                  Scope             => Global_Scope,
                  Declaration_Info  => Decl_Info);
            end if;

      end;
   else
      --  look for dependency declaration
      begin
         Decl_Info := Find_Dependency_Declaration
           (File                 => Global_LI_File,
            Symbol_Name          => Ref_Id,
            Filename             => Typedef.Buffer
              (Typedef.File_Name.First .. Typedef.File_Name.Last),
            Location             => Typedef.Start_Position);
      exception
         when Declaration_Not_Found => -- dep decl does not yet exist

            Original_Type (Ref_Id, Desc, Success);

            if not Success then
               Fail ("unable to find type for typedef " & Ref_Id);
               Free (Desc);
               Free (Typedef);
               return;
            end if;

            if Desc.Ancestor_Point = Invalid_Point then
               --  unknown parent
               Insert_Dependency_Declaration
                 (Handler           => LI_Handler (Global_CPP_Handler),
                  File              => Global_LI_File,
                  List              => Global_LI_File_List,
                  Symbol_Name       => Ref_Id,
                  Source_Filename   => Ref.Buffer
                    (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location          => Typedef.Start_Position,
                  Kind              => Desc.Kind,
                  Scope             => Global_Scope,
                  Referred_Filename => Typedef.Buffer
                    (Typedef.File_Name.First .. Typedef.File_Name.Last),
                  Declaration_Info  => Decl_Info);
            elsif Desc.Ancestor_Point = Predefined_Point then
               --  typedef for builtin type
               Insert_Dependency_Declaration
                 (Handler           => LI_Handler (Global_CPP_Handler),
                  File              => Global_LI_File,
                  List              => Global_LI_File_List,
                  Symbol_Name       => Ref_Id,
                  Source_Filename   => Ref.Buffer
                    (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location          => Typedef.Start_Position,
                  Parent_Location   => Predefined_Point,
                  Kind              => Desc.Kind,
                  Scope             => Global_Scope,
                  Referred_Filename => Typedef.Buffer
                    (Typedef.File_Name.First .. Typedef.File_Name.Last),
                  Declaration_Info  => Decl_Info);
            else
               --  parent type found
               Insert_Dependency_Declaration
                 (Handler           => LI_Handler (Global_CPP_Handler),
                  File              => Global_LI_File,
                  List              => Global_LI_File_List,
                  Symbol_Name       => Ref_Id,
                  Source_Filename   => Ref.Buffer
                    (Ref.File_Name.First .. Ref.File_Name.Last),
                  Location          => Typedef.Start_Position,
                  Parent_Location   => Desc.Ancestor_Point,
                  Parent_Filename   => Desc.Ancestor_Filename.all,
                  Kind              => Desc.Kind,
                  Scope             => Global_Scope,
                  Referred_Filename => Typedef.Buffer
                    (Typedef.File_Name.First .. Typedef.File_Name.Last),
                  Declaration_Info  => Decl_Info);
            end if;

      end;
   end if;

   Insert_Reference
     (Declaration_Info     => Decl_Info,
      File                 => Global_LI_File,
      Source_Filename      =>
        Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last),
      Location             => Ref.Position,
      Kind                 => Reference);

   Free (Typedef);

exception
   when DB_Error | Not_Found  =>
      Fail ("unable to find typedef " & Ref_Id);

end Fu_To_T_Handler;


------------------------
--  Fu_To_Un_Handler  --
------------------------

procedure Fu_To_Un_Handler (Ref : TO_Table)
is
   Ref_Id : constant String := Ref.Buffer
     (Ref.Referred_Symbol_Name.First .. Ref.Referred_Symbol_Name.Last);
   Union_Desc : CType_Description;
   Union_Def  : UN_Table;
   Success    : Boolean;
   Decl_Info  : E_Declaration_Info_List;
begin

   Info ("Fu_To_Un_Handler: " & Ref_Id);

   Find_Union
     (Type_Name      => Ref_Id,
      Desc           => Union_Desc,
      Union_Def      => Union_Def,
      Success        => Success);

   if not Success then
      Fail ("unable to find union " & Ref_Id);
      return;
   end if;

   if Ref.Buffer (Ref.File_Name.First .. Ref.File_Name.Last) /=
         Union_Def.Buffer (Union_Def.File_Name.First ..
                                    Union_Def.File_Name.Last)
   then
      begin
         Decl_Info :=
           Find_Dependency_Declaration
             (File        => Global_LI_File,
              Symbol_Name => Union_Def.Buffer
                (Union_Def.Name.First .. Union_Def.Name.Last),
              Kind        => Record_Type,
              Location    => Union_Def.Start_Position,
              Filename    => Union_Def.Buffer
                (Union_Def.File_Name.First .. Union_Def.File_Name.Last));
      exception
         when Declaration_Not_Found =>
            Insert_Dependency_Declaration
              (Handler            => LI_Handler (Global_CPP_Handler),
               File               => Global_LI_File,
               List               => Global_LI_File_List,
               Symbol_Name        => Union_Def.Buffer
                 (Union_Def.Name.First .. Union_Def.Name.Last),
               Referred_Filename  => Union_Def.Buffer
                 (Union_Def.File_Name.First .. Union_Def.File_Name.Last),
               Source_Filename    => Ref.Buffer
                 (Ref.File_Name.First .. Ref.File_Name.Last),
               Location           => Union_Def.Start_Position,
               Kind               => Record_Type,
               Scope              => Global_Scope,
               Declaration_Info   => Decl_Info);
      end;
   else
      begin
         Decl_Info :=
           Find_Declaration
             (File        => Global_LI_File,
              Symbol_Name => Union_Def.Buffer
                (Union_Def.Name.First .. Union_Def.Name.Last),
              Kind        => Record_Type,
              Location    => Union_Def.Start_Position);
      exception
         when Declaration_Not_Found =>
            Insert_Declaration
              (Handler            => LI_Handler (Global_CPP_Handler),
               File               => Global_LI_File,
               List               => Global_LI_File_List,
               Symbol_Name        => Union_Def.Buffer
                 (Union_Def.Name.First .. Union_Def.Name.Last),
               Source_Filename    => Ref.Buffer
                 (Ref.File_Name.First .. Ref.File_Name.Last),
               Location           => Union_Def.Start_Position,
               Kind               => Record_Type,
               Scope              => Global_Scope,
               Declaration_Info   => Decl_Info);
      end;
   end if;
   Insert_Reference
     (File              => Global_LI_File,
      Declaration_Info  => Decl_Info,
      Source_Filename   => Ref.Buffer
        (Ref.File_Name.First .. Ref.File_Name.Last),
      Location          => Ref.Position,
      Kind              => Reference);
   Free (Union_Def);
   Free (Union_Desc);

end Fu_To_Un_Handler;


--------------------
-- Sym_CL_Handler --
--------------------

procedure Sym_CL_Handler (Sym : FIL_Table)
is
   Decl_Info  : E_Declaration_Info_List;
   Desc       : CType_Description;
   Class_Def  : CL_Table;
   Success    : Boolean;
   P          : Pair_Ptr;
   Super      : IN_Table;
   Super_Def  : CL_Table;
   Super_Desc : CType_Description;
begin

   Info ("Sym_CL_Hanlder: """
         & Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last)
         & """");

   Find_Class
     (Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
      Desc,
      Class_Def,
      Success);

   if not Success then
      return;
   end if;

   Insert_Declaration
     (Handler               => LI_Handler (Global_CPP_Handler),
      File                  => Global_LI_File,
      List                  => Global_LI_File_List,
      Symbol_Name           =>
        Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
      Source_Filename       =>
        Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
      Location              => Sym.Start_Position,
      Kind                  => Record_Type,
      Scope                 => Global_Scope,
      End_Of_Scope_Location => Class_Def.End_Position,
      Declaration_Info      => Decl_Info);

   --  Adjust EOS reference kind
   Decl_Info.Value.Declaration.End_Of_Scope.Kind := End_Of_Spec;

   --  Find all the base classes for this one
   Set_Cursor
     (SN_Table (SN_IN),
      By_Key,
      --  Use name from Class_Def for it does not hold <> when
      --  template class is encountered
      Class_Def.Buffer (Class_Def.Name.First .. Class_Def.Name.Last)
         & Field_Sep,
      False);

   loop
      P := Get_Pair (SN_Table (SN_IN), Next_By_Key);
      exit when P = null;
      Super := Parse_Pair (P.all);
      Info ("Found base class: "
         & Super.Buffer (Super.Base_Class.First .. Super.Base_Class.Last));
      --  Lookup base class definition to find its precise location
      Find_Class
       (Super.Buffer (Super.Base_Class.First .. Super.Base_Class.Last),
        Super_Desc,
        Super_Def,
        Success);
      if Success then -- if found, add it to parent list
         Add_Parent
           (Decl_Info,
            Global_LI_File_List,
            Super_Def.Buffer
              (Super_Def.File_Name.First .. Super_Def.File_Name.Last),
            Super_Def.Start_Position);
         Free (Super_Desc);
         Free (Super_Def);
      end if;
      Free (Super);
      Free (P);
   end loop;

   Free (Desc);
   Free (Class_Def);
exception
   when DB_Error => -- something went wrong, ignore it
      null;
end Sym_CL_Handler;

---------------------
-- Sym_CON_Handler --
---------------------

procedure Sym_CON_Handler (Sym : FIL_Table)
--  NOTE: this handler is called from fu-to-con handler as well!!!
is
   Desc              : CType_Description;
   Var               : GV_Table;
   Success           : Boolean;
   Decl_Info         : E_Declaration_Info_List;
   Attributes        : SN_Attributes;
   Scope             : E_Scope := Global_Scope;
begin
   Info ("Sym_CON_Handler: """
         & Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last)
         & """");

   if not Is_Open (SN_Table (CON)) then
      --  CON table does not exist, nothing to do ...
      return;
   end if;

   --  Lookup variable type
   Var := Find (SN_Table (CON), Sym.Buffer
      (Sym.Identifier.First .. Sym.Identifier.Last));
   Type_Name_To_Kind (Var.Buffer
      (Var.Value_Type.First .. Var.Value_Type.Last), Desc, Success);

   if not Success then -- type not found
      --  ?? Is ot OK to set E_Kind to Unresolved_Entity for global variables
      --  with unknown type?
      Desc.Kind := Unresolved_Entity;
   end if;

   Attributes := SN_Attributes (Var.Attributes);

   if (Attributes and SN_STATIC) = SN_STATIC then
      Scope := Static_Local;
   end if;

   if Desc.Parent_Point = Invalid_Point then
      Insert_Declaration
        (Handler           => LI_Handler (Global_CPP_Handler),
         File              => Global_LI_File,
         List              => Global_LI_File_List,
         Symbol_Name       =>
           Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
         Source_Filename   =>
           Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Location          => Sym.Start_Position,
         Kind              => Type_To_Object (Desc.Kind),
         Scope             => Scope,
         Declaration_Info  => Decl_Info);
   else
      Insert_Declaration
        (Handler           => LI_Handler (Global_CPP_Handler),
         File              => Global_LI_File,
         List              => Global_LI_File_List,
         Symbol_Name       =>
           Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
         Source_Filename   =>
           Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Location          => Sym.Start_Position,
         Kind              => Type_To_Object (Desc.Kind),
         Scope             => Scope,
         Parent_Location   => Desc.Parent_Point,
         Parent_Filename   => Desc.Parent_Filename.all,
         Declaration_Info  => Decl_Info);

      --  add reference to the type of this variable
      if Desc.IsTemplate then
         --  template specialization
         Refer_Type
           (Var.Buffer (Var.Value_Type.First .. Var.Value_Type.Last),
            Desc.Parent_Point,
            Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
            Sym.Start_Position,
            Instantiation_Reference);
      else
         --  default reference kind
         Refer_Type
           (Var.Buffer (Var.Value_Type.First .. Var.Value_Type.Last),
            Desc.Parent_Point,
            Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
            Sym.Start_Position);
      end if;

   end if;

   Free (Var);
   Free (Desc);
exception
   when  DB_Error |   -- non-existent table
         Not_Found => -- no such variable
      null;           -- ignore error
end Sym_CON_Handler;


-------------------------
-- Sym_Default_Handler --
-------------------------

--  This is default handler for symbols, which are not registered
--  in Symbols_Handlers.

procedure Sym_Default_Handler
  (Sym : FIL_Table)
is
   --  pragma Unreferenced (Sym);
begin
   Info ("Sym_Default_Hanlder: """
         & Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last)
         & """ : " & Symbol_Type'Image (Sym.Symbol));
   null;
end Sym_Default_Handler;

--------------------
-- Sym_E_Handler --
--------------------

procedure Sym_E_Handler (Sym : FIL_Table)
is
   Decl_Info : E_Declaration_Info_List;
   E_Id      : constant String := Sym.Buffer
     (Sym.Identifier.First .. Sym.Identifier.Last);
begin

   Info ("Sym_E_Hanlder: """ & E_Id & """");

   Insert_Declaration
     (Handler           => LI_Handler (Global_CPP_Handler),
      File              => Global_LI_File,
      List              => Global_LI_File_List,
      Symbol_Name       => E_Id,
      Source_Filename   =>
        Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
      Location          => Sym.Start_Position,
      Kind              => Enumeration_Type,
      Scope             => Global_Scope,
      Declaration_Info  => Decl_Info);

end Sym_E_Handler;

--------------------
-- Sym_EC_Handler --
--------------------

procedure Sym_EC_Handler (Sym : FIL_Table)
is
   Decl_Info : E_Declaration_Info_List;
   Ec_Id     : constant String := Sym.Buffer
     (Sym.Identifier.First ..  Sym.Identifier.Last);
   Desc      : CType_Description;
   Has_Enum  : Boolean := False;
begin

   Info ("Sym_EC_Hanlder: '" & Ec_Id & "'");

   --  looking for enum, which contains given enum constant (EC)
   if Is_Open (SN_Table (EC)) and then Is_Open (SN_Table (E)) then
      declare
         EC_Def : EC_Table := Find (SN_Table (EC), Ec_Id, Sym.Start_Position);
         E_Def  : E_Table;
      begin
         Find_Enum
           (EC_Def.Buffer
              (EC_Def.Enumeration_Name.First ..
               EC_Def.Enumeration_Name.Last),
            Desc, E_Def, Has_Enum);
         Free (E_Def);
         Free (EC_Def);
      exception
         when DB_Error | Not_Found => -- ignore
            Free (E_Def);
            Free (EC_Def);
      end;
   end if;

   if Has_Enum then -- corresponding enumeration found
      Insert_Declaration
        (Handler           => LI_Handler (Global_CPP_Handler),
         File              => Global_LI_File,
         List              => Global_LI_File_List,
         Symbol_Name       => Ec_Id,
         Source_Filename   =>
           Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Location          => Sym.Start_Position,
         Kind              => Enumeration_Literal,
         Parent_Location   => Desc.Parent_Point,
         Parent_Filename   => Desc.Parent_Filename.all,
         Scope             => Global_Scope,
         Declaration_Info  => Decl_Info);
   else
      Fail ("could not find enum for '" & Ec_Id & "'");
      Insert_Declaration
        (Handler           => LI_Handler (Global_CPP_Handler),
         File              => Global_LI_File,
         List              => Global_LI_File_List,
         Symbol_Name       => Ec_Id,
         Source_Filename   =>
           Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Location          => Sym.Start_Position,
         Kind              => Enumeration_Literal,
         Scope             => Global_Scope,
         Declaration_Info  => Decl_Info);
   end if;

end Sym_EC_Handler;

--------------------
-- Sym_FD_Handler --
--------------------

procedure Sym_FD_Handler (Sym : FIL_Table)
is
   Target_Kind  : E_Kind;
   Decl_Info    : E_Declaration_Info_List;
   P            : Pair_Ptr;
   First_FD_Pos : Point := Invalid_Point;
   FD_Tab       : FD_Table;
   FD_Tab_Tmp   : FD_Table;
   Attributes   : SN_Attributes;
   IsStatic     : Boolean;
   Match        : Boolean;
begin
   Info ("Sym_FD_Hanlder: """
         & Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last)
         & """");

   --  Find this symbol
   FD_Tab := Find
     (SN_Table (FD),
      Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
      Sym.Start_Position,
      Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last));

   Attributes := SN_Attributes (FD_Tab.Attributes);
   IsStatic   := (Attributes and SN_STATIC) = SN_STATIC;

   Set_Cursor
     (SN_Table (FD),
      By_Key,
      Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last) & Field_Sep,
      False);

   loop
      P := Get_Pair (SN_Table (FD), Next_By_Key);
      exit when P = null;
      FD_Tab_Tmp := Parse_Pair (P.all);
      Free (P);
      --  Update position of the first forward declaration
      --  We have to compare prototypes of all global functions
      --  if this is a global function, or only local (static)
      --  ones if this is a static function
      Match := True;
      if IsStatic then
         Match := Match and Sym.Buffer (Sym.File_Name.First ..
                                        Sym.File_Name.Last)
               = FD_Tab_Tmp.Buffer (FD_Tab_Tmp.File_Name.First ..
                                    FD_Tab_Tmp.File_Name.Last);
      end if;

      Match := Match and Cmp_Prototypes
        (FD_Tab.Buffer,
         FD_Tab_Tmp.Buffer,
         FD_Tab.Arg_Types,
         FD_Tab_Tmp.Arg_Types,
         FD_Tab.Return_Type,
         FD_Tab_Tmp.Return_Type);

      if (Match and then First_FD_Pos = Invalid_Point)
            or else FD_Tab_Tmp.Start_Position < First_FD_Pos then
         First_FD_Pos := FD_Tab_Tmp.Start_Position;
      end if;
      Free (FD_Tab_Tmp);
   end loop;

   pragma Assert (First_FD_Pos /= Invalid_Point, "DB inconsistency");

   if FD_Tab.Buffer (FD_Tab.Return_Type.First ..
                     FD_Tab.Return_Type.Last) = "void" then
      Target_Kind := Non_Generic_Procedure;
   else
      Target_Kind := Non_Generic_Function_Or_Operator;
   end if;
   Free (FD_Tab);

   --  create declaration (if it has not been already created)
   Insert_Declaration
     (Handler           => LI_Handler (Global_CPP_Handler),
      File              => Global_LI_File,
      List              => Global_LI_File_List,
      Symbol_Name       =>
        Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
      Source_Filename   =>
        Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
      Location          => First_FD_Pos,
      Kind              => Target_Kind,
      Scope             => Global_Scope,
      Declaration_Info  => Decl_Info);

   --  for all subsequent declarations, add reference to the first decl
   if Sym.Start_Position /= First_FD_Pos then
      Insert_Reference
        (Decl_Info,
         Global_LI_File,
         Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Sym.Start_Position,
         Reference);
   end if;
exception
   when DB_Error | Not_Found =>
      Fail ("unable to find function " &
            Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last));
end Sym_FD_Handler;

--------------------
-- Sym_FU_Handler --
--------------------

procedure Sym_FU_Handler (Sym : FIL_Table)
is
   Decl_Info      : E_Declaration_Info_List := null;
   Target_Kind    : E_Kind;
   Sym_Type       : SN.String_Access :=
                  new String'(ASCII.NUL & ASCII.NUL & ASCII.NUL);
   tmp_int        : Integer;
   P              : Pair_Ptr;
   FU_Tab         : FU_Table;
   MI_Tab         : MI_Table;
   Start_Position : Point := Sym.Start_Position;
   Body_Position  : Point := Invalid_Point;
   End_Position   : Point;
   IsTemplate     : Boolean := False;

   Fu_Id          : constant String := Sym.Buffer
     (Sym.Identifier.First .. Sym.Identifier.Last);

begin
   Info ("Sym_FU_Hanlder: """
         & Sym.Buffer (Sym.Class.First .. Sym.Class.Last) & "."
         & Fu_Id
         & """");

   if Sym.Symbol = MI then
      declare
         Class_Def    : CL_Table;
      begin
         MI_Tab := Find (SN_Table (MI),
             Sym.Buffer (Sym.Class.First .. Sym.Class.Last),
             Fu_Id,
             Sym.Start_Position,
             Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last));
         begin -- check if this class is template
            Class_Def := Find
              (SN_Table (CL), Sym.Buffer (Sym.Class.First .. Sym.Class.Last));
            IsTemplate := Class_Def.Template_Parameters.First
               < Class_Def.Template_Parameters.Last;
            Free (Class_Def);
         exception
            when DB_Error | Not_Found =>
               null;
         end;
         if MI_Tab.Buffer (MI_Tab.Return_Type.First ..
                           MI_Tab.Return_Type.Last) = "void" then
            if IsTemplate then
               Target_Kind := Generic_Procedure;
            else
               Target_Kind := Non_Generic_Procedure;
            end if;
         else
            if IsTemplate then
               Target_Kind := Generic_Function_Or_Operator;
            else
               Target_Kind := Non_Generic_Function_Or_Operator;
            end if;
         end if;
         End_Position := MI_Tab.End_Position;
      exception
         when DB_Error | Not_Found =>
            Fail ("unable to find method "
                  & Sym.Buffer (Sym.Class.First .. Sym.Class.Last) & "."
                  & Fu_Id);
            return;
      end;
   else
      begin
         FU_Tab := Find
           (SN_Table (FU),
            Fu_Id,
            Sym.Start_Position,
            Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last));
         if FU_Tab.Buffer (FU_Tab.Return_Type.First ..
                           FU_Tab.Return_Type.Last) = "void" then
            Target_Kind := Non_Generic_Procedure;
         else
            Target_Kind := Non_Generic_Function_Or_Operator;
         end if;
         End_Position := FU_Tab.End_Position;
      exception
         when DB_Error | Not_Found =>
            Fail ("unable to find function " & Fu_Id);
            return;
      end;
   end if;

   --  Detect forward declaration. If there are many declarations
   --  we should not try do interpret them, 'cause it may be
   --  overloading.
   --  If exist only one, Start_Position
   --  should point to it and we have to add Body_Entity reference
   --  Otherwise Start_Position should point directly to the body.
   --  We should also try to find GPS declaration created during
   --  FD processing and not create new declaration.
   if Sym.Symbol = MI then
      Decl_Info      := Find_First_Forward_Declaration
        (MI_Tab.Buffer,
         MI_Tab.Class,
         MI_Tab.Name,
         MI_Tab.File_Name,
         MI_Tab.Return_Type,
         MI_Tab.Arg_Types);
      if Decl_Info /= null then -- Body_Entity is inserted only w/ fwd decl
         Body_Position  := Sym.Start_Position;
      end if;
   else
      --  Try to find forward declaration
      Decl_Info      := Find_First_Forward_Declaration
        (FU_Tab.Buffer,
         FU_Tab.Name,
         FU_Tab.File_Name,
         FU_Tab.Return_Type,
         FU_Tab.Arg_Types);
      if Decl_Info /= null then -- Body_Entity is inserted only w/ fwd decl
         Body_Position  := Sym.Start_Position;
      end if;
   end if;

   if Decl_Info = null then
      Insert_Declaration
        (Handler               => LI_Handler (Global_CPP_Handler),
         File                  => Global_LI_File,
         List                  => Global_LI_File_List,
         Symbol_Name           => Fu_Id,
         Source_Filename       =>
           Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Location              => Start_Position,
         Kind                  => Target_Kind,
         Scope                 => Global_Scope,
         End_Of_Scope_Location => End_Position,
         Declaration_Info      => Decl_Info);
   else
      Set_End_Of_Scope (Decl_Info, End_Position);
   end if;

   if Body_Position /= Invalid_Point then
      Insert_Reference
        (Decl_Info,
         Global_LI_File,
         Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Body_Position,
         Body_Entity);
   end if;


   --  Declaration inserted. Now we need to check the body for external
   --  references.

   tmp_int := 1;
   To_String (Sym.Symbol, Sym_Type, tmp_int);
   Set_Cursor
     (SN_Table (TO),
      Position => By_Key,
      Key => Sym.Buffer (Sym.Class.First .. Sym.Class.Last) & Field_Sep &
             Fu_Id &
             Field_Sep & Sym_Type.all,
      Exact_Match => False);

   loop
         P := Get_Pair (SN_Table (TO), Next_By_Key);
         exit when P = null;

         declare
            --  ???:
            --  SN has only line number in .to table. So, to get exact
            --  position we are getting that line from source file and
            --  calling corresponding handler for EVERY
            --  occurrence of that symbol in that line.
            Ref      : TO_Table := Parse_Pair (P.all);
            Buffer   : SN.String_Access;
            Slice    : Segment;
            PRef     : TO_Table;  -- Ref with exact position
            P        : Integer;
            S        : String  :=
                  Ref.Buffer (Ref.Referred_Symbol_Name.First
                                    .. Ref.Referred_Symbol_Name.Last);
            Matches  : Match_Array (0 .. 0);
            Pat      : Pattern_Matcher := Compile ("\b" & S & "\b");
            Our_Ref  : Boolean;
         begin
            if Sym.Symbol = MI then
               Our_Ref := Cmp_Arg_Types
                 (Ref.Buffer,
                  MI_Tab.Buffer,
                  Ref.Caller_Argument_Types,
                  MI_Tab.Arg_Types);
            else
               Our_Ref := Cmp_Arg_Types
                 (Ref.Buffer,
                  FU_Tab.Buffer,
                  Ref.Caller_Argument_Types,
                  FU_Tab.Arg_Types);
            end if;

            if Our_Ref then
               File_Buffer.Get_Line (Ref.Position.Line, Buffer, Slice);
               P := Slice.First;
               loop
                  Match (Pat, Buffer.all (P .. Slice.Last), Matches);
                  exit when Matches (0) = No_Match or Ref.Symbol = Undef;
                  P := Matches (0).Last + 1;
                  PRef := Ref;
                  --  conversion to column
                  PRef.Position.Column := Matches (0).First - Slice.First;
                  if (Fu_To_Handlers (Ref.Referred_Symbol) /= null) then
                     Fu_To_Handlers (Ref.Referred_Symbol)(PRef);
                  end if;
               end loop;
            end if;
            Free (Ref);
         exception
            when others =>
               --  unexpected exception in Fu_To_XX handler
               Free (Ref);
               --  ??? Probably we want to report this exception and continue
               --  to work further, but now we reraise that exception
               raise;
         end;

         Free (P);
   end loop;

   if Sym.Symbol = MI then
      Free (MI_Tab);
   else
      Free (FU_Tab);
   end if;

exception
   when DB_Error => null; -- non-existent table .to, ignore it

end Sym_FU_Handler;

--------------------
-- Sym_GV_Handler --
--------------------

procedure Sym_GV_Handler (Sym : FIL_Table)
--  NOTE: this handler is called from fu-to-gv handler as well
is
   Desc              : CType_Description;
   Var               : GV_Table;
   Success           : Boolean;
   Decl_Info         : E_Declaration_Info_List;
   Attributes        : SN_Attributes;
   Scope             : E_Scope := Global_Scope;
begin
   Info ("Sym_GV_Handler: """
         & Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last)
         & """");

   if not Is_Open (SN_Table (GV)) then
      --  GV table does not exist, nothing to do ...
      return;
   end if;

   --  Lookup variable type
   Var := Find (SN_Table (GV), Sym.Buffer
      (Sym.Identifier.First .. Sym.Identifier.Last));

   Type_Name_To_Kind (Var.Buffer
      (Var.Value_Type.First .. Var.Value_Type.Last), Desc, Success);

   if not Success then -- type not found
      --  ?? Is ot OK to set E_Kind to Unresolved_Entity for global variables
      --  with unknown type?
      Desc.Kind := Unresolved_Entity;
   end if;

   Attributes := SN_Attributes (Var.Attributes);

   if (Attributes and SN_STATIC) = SN_STATIC then
      Scope := Static_Local;
   end if;

   if Desc.Parent_Point = Invalid_Point then
      Insert_Declaration
        (Handler           => LI_Handler (Global_CPP_Handler),
         File              => Global_LI_File,
         List              => Global_LI_File_List,
         Symbol_Name       =>
           Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
         Source_Filename   =>
           Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Location          => Sym.Start_Position,
         Kind              => Type_To_Object (Desc.Kind),
         Scope             => Scope,
         Declaration_Info  => Decl_Info);
   else
      Insert_Declaration
        (Handler           => LI_Handler (Global_CPP_Handler),
         File              => Global_LI_File,
         List              => Global_LI_File_List,
         Symbol_Name       =>
           Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
         Source_Filename   =>
           Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Location          => Sym.Start_Position,
         Kind              => Type_To_Object (Desc.Kind),
         Scope             => Scope,
         Parent_Location   => Desc.Parent_Point,
         Parent_Filename   => Desc.Parent_Filename.all,
         Declaration_Info  => Decl_Info);

      --  add reference to the type of this variable
      if Desc.IsTemplate then
         --  template specialization
         Refer_Type
           (Var.Buffer (Var.Value_Type.First .. Var.Value_Type.Last),
            Desc.Parent_Point,
            Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
            Sym.Start_Position,
            Instantiation_Reference);
      else
         --  default reference kind
         Refer_Type
           (Var.Buffer (Var.Value_Type.First .. Var.Value_Type.Last),
            Desc.Parent_Point,
            Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
            Sym.Start_Position);
      end if;
   end if;

   Free (Var);
   Free (Desc);
exception
   when  DB_Error |   -- non-existent table
         Not_Found => -- no such variable
      null;           -- ignore error
end Sym_GV_Handler;

--------------------
-- Sym_IU_Handler --
--------------------

procedure Sym_IU_Handler (Sym : FIL_Table) is
begin
   Info ("Sym_IU_Handler: """
         & Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last)
         & """");

   Insert_Dependency
     (Handler           => LI_Handler (Global_CPP_Handler),
      File              => Global_LI_File,
      List              => Global_LI_File_List,
      Source_Filename   =>
        Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
      Referred_Filename =>
        Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last));

end Sym_IU_Handler;



--------------------
-- Sym_IV_Handler --
--------------------

procedure Sym_IV_Handler (Sym : FIL_Table)
is
   Inst_Var        : IV_Table;
   Decl_Info       : E_Declaration_Info_List;
   Success         : Boolean;
   Desc            : CType_Description;
begin
   Info ("Sym_IV_Handler: """
         & Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last)
         & """");

   if not Is_Open (SN_Table (IV)) then
      --  IV table does not exist, nothing to do ...
      return;
   end if;

   --  Lookup instance variable
   Inst_Var := Find
     (SN_Table (IV),
      Sym.Buffer (Sym.Class.First .. Sym.Class.Last),
      Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last));

   --  Determine its type
   Type_Name_To_Kind
     (Inst_Var.Buffer
        (Inst_Var.Value_Type.First .. Inst_Var.Value_Type.Last),
      Desc,
      Success);

   if not Success then -- failed to determine type
      --  if the variable belongs to a template, the unknown type
      --  may be template parameter. Check it.
      --  TODO Here we should parse class template arguments and
      --  locate the type in question. Not implemented yet
      Desc.Kind           := Private_Type;
      Desc.IsVolatile     := False;
      Desc.IsConst        := False;
      Desc.Parent_Point   := Invalid_Point;
      Desc.Ancestor_Point := Invalid_Point;
      Desc.Builtin_Name   := null;
      --  Free (Inst_Var);
      --  return;
   end if;

   if Desc.Parent_Point = Invalid_Point then
      Insert_Declaration
        (Handler           => LI_Handler (Global_CPP_Handler),
         File              => Global_LI_File,
         List              => Global_LI_File_List,
         Symbol_Name       =>
           Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
         Source_Filename   =>
           Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Location          => Sym.Start_Position,
         Kind              => Type_To_Object (Desc.Kind),
         Scope             => Local_Scope,
         Declaration_Info  => Decl_Info);
   else
      Insert_Declaration
        (Handler           => LI_Handler (Global_CPP_Handler),
         File              => Global_LI_File,
         List              => Global_LI_File_List,
         Symbol_Name       =>
           Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
         Source_Filename   =>
           Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Location          => Sym.Start_Position,
         Kind              => Desc.Kind,
         Scope             => Local_Scope,
         Parent_Location   => Desc.Parent_Point,
         Parent_Filename   => Desc.Parent_Filename.all,
         Declaration_Info  => Decl_Info);

      --  add reference to the type of this field
      Refer_Type
        (Inst_Var.Buffer
           (Inst_Var.Value_Type.First .. Inst_Var.Value_Type.Last),
         Desc.Parent_Point,
         Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Sym.Start_Position);
   end if;

   Free (Desc);
   Free (Inst_Var);
exception
   when  DB_Error |   -- non-existent table
         Not_Found => -- no such variable
      null;           -- ignore error
end Sym_IV_Handler;


--------------------
-- Sym_MA_Handler --
--------------------

procedure Sym_MA_Handler (Sym : FIL_Table)
is
   tmp_ptr    : E_Declaration_Info_List;
begin
   Info ("Sym_MA_Handler: """
         & Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last)
         & """");

   Insert_Declaration
     (Handler           => LI_Handler (Global_CPP_Handler),
      File              => Global_LI_File,
      List              => Global_LI_File_List,
      Symbol_Name       =>
        Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
      Source_Filename   =>
        Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
      Location          => Sym.Start_Position,
      Kind              => Unresolved_Entity,
      Scope             => Global_Scope,
      Declaration_Info  => tmp_ptr);

end Sym_MA_Handler;


--------------------
-- Sym_MD_Handler --
--------------------

procedure Sym_MD_Handler (Sym : FIL_Table)
is
   Target_Kind  : E_Kind;
   Decl_Info    : E_Declaration_Info_List;
   P            : Pair_Ptr;
   First_MD_Pos : Point := Invalid_Point;
   MD_Tab       : MD_Table;
   MD_Tab_Tmp   : MD_Table;
   IsTemplate   : Boolean := False;
   use DB_Structures.Segment_Vector;

begin
   Info ("Sym_MD_Hanlder: """
         & Sym.Buffer (Sym.Class.First .. Sym.Class.Last) & "::"
         & Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last)
         & """");

   --  Find this symbol
   MD_Tab := Find
     (SN_Table (MD),
      Sym.Buffer (Sym.Class.First .. Sym.Class.Last),
      Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
      Sym.Start_Position,
      Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last));

   Set_Cursor
     (SN_Table (MD),
      By_Key,
      Sym.Buffer (Sym.Class.First .. Sym.Class.Last) & Field_Sep
         & Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last)
         & Field_Sep,
      False);

   loop
      P := Get_Pair (SN_Table (MD), Next_By_Key);
      exit when P = null;
      MD_Tab_Tmp := Parse_Pair (P.all);
      Free (P);
      --  Update position of the first forward declaration
      if Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last)
         = MD_Tab_Tmp.Buffer (MD_Tab_Tmp.File_Name.First ..
                              MD_Tab_Tmp.File_Name.Last)
         and then Cmp_Prototypes
           (MD_Tab.Buffer,
            MD_Tab_Tmp.Buffer,
            MD_Tab.Arg_Types,
            MD_Tab_Tmp.Arg_Types,
            MD_Tab.Return_Type,
            MD_Tab_Tmp.Return_Type)
         and then ((First_MD_Pos = Invalid_Point)
         or else MD_Tab_Tmp.Start_Position < First_MD_Pos) then
         First_MD_Pos := MD_Tab_Tmp.Start_Position;
      end if;
      Free (MD_Tab_Tmp);
   end loop;

   pragma Assert (First_MD_Pos /= Invalid_Point, "DB inconsistency");

   declare
      Class_Def    : CL_Table;
   begin -- check if this class is template
      Class_Def := Find
        (SN_Table (CL), Sym.Buffer (Sym.Class.First .. Sym.Class.Last));
      IsTemplate := Class_Def.Template_Parameters.First
         < Class_Def.Template_Parameters.Last;
      Free (Class_Def);
   exception
      when DB_Error | Not_Found =>
         null;
   end;

   if MD_Tab.Buffer (MD_Tab.Return_Type.First ..
                     MD_Tab.Return_Type.Last) = "void" then
      if IsTemplate then
         Target_Kind := Generic_Procedure;
      else
         Target_Kind := Non_Generic_Procedure;
      end if;
   else
      if IsTemplate then
         Target_Kind := Generic_Function_Or_Operator;
      else
         Target_Kind := Non_Generic_Function_Or_Operator;
      end if;
   end if;
   Free (MD_Tab);

   --  create declaration (if it has not been already created)
   Insert_Declaration
     (Handler           => LI_Handler (Global_CPP_Handler),
      File              => Global_LI_File,
      List              => Global_LI_File_List,
      Symbol_Name       =>
         Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
      Source_Filename   =>
         Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
      Location          => First_MD_Pos,
      Kind              => Target_Kind,
      Scope             => Global_Scope,
      Declaration_Info  => Decl_Info);

   --  for all subsequent declarations, add reference to the first decl
   if Sym.Start_Position /= First_MD_Pos then
      Insert_Reference
        (Decl_Info,
         Global_LI_File,
         Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
         Sym.Start_Position,
         Reference);
   end if;
exception
   when DB_Error | Not_Found =>
      Fail ("unable to find method " &
            Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last));
end Sym_MD_Handler;

--------------------
-- Sym_T_Handler --
--------------------

procedure Sym_T_Handler (Sym : FIL_Table)
is
   Decl_Info  : E_Declaration_Info_List;
   Desc       : CType_Description;
   Success    : Boolean;
   Identifier : constant String :=
     Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last);
begin

   Info ("Sym_T_Hanlder: """ & Identifier & """");

   if not Is_Open (SN_Table (T)) then
      --  .t table does not exist, nothing to do
      return;
   end if;

   --  find original type for given typedef
   Original_Type (Identifier, Desc, Success);

   if Success then
      --  we know E_Kind for original type
      --  Ancestor_Point and Ancestor_Filename has information about
      --  parent type (do not mess with Parent_xxx in CType_Description)

      if Desc.Ancestor_Point = Invalid_Point then
         --  unknown parent
         Insert_Declaration
           (Handler           => LI_Handler (Global_CPP_Handler),
            File              => Global_LI_File,
            List              => Global_LI_File_List,
            Symbol_Name       => Identifier,
            Source_Filename   =>
              Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
            Location          => Sym.Start_Position,
            Kind              => Desc.Kind,
            Scope             => Global_Scope,
            Declaration_Info  => Decl_Info);

      elsif Desc.Ancestor_Point = Predefined_Point then
         --  parent type is builtin: set parent location to predefined one
         --  ??? Builtin_Name is not used anywhere. We should
         --  use it (e.g. for a field like Predefined_Type_Name)
         Insert_Declaration
           (Handler           => LI_Handler (Global_CPP_Handler),
            File              => Global_LI_File,
            List              => Global_LI_File_List,
            Symbol_Name       => Identifier,
            Source_Filename   =>
              Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
            Location          => Sym.Start_Position,
            Parent_Location   => Predefined_Point,
            Kind              => Desc.Kind,
            Scope             => Global_Scope,
            Declaration_Info  => Decl_Info);

      else
         --  Set parent location to ancestor location
         Insert_Declaration
           (Handler           => LI_Handler (Global_CPP_Handler),
            File              => Global_LI_File,
            List              => Global_LI_File_List,
            Symbol_Name       => Identifier,
            Source_Filename   =>
              Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
            Location          => Sym.Start_Position,
            Parent_Filename   => Desc.Ancestor_Filename.all,
            Parent_Location   => Desc.Ancestor_Point,
            Kind              => Desc.Kind,
            Scope             => Global_Scope,
            Declaration_Info  => Decl_Info);

      end if;

   else

      --  could not get E_Kind for the original type
      Fail ("unable to find type for typedef " & Identifier);

   end if;

   Free (Desc);

end Sym_T_Handler;

--------------------
-- Sym_UN_Handler --
--------------------

procedure Sym_UN_Handler (Sym : FIL_Table)
is
   Decl_Info : E_Declaration_Info_List;
   Desc      : CType_Description;
   Union_Def : UN_Table;
   Success   : Boolean;
begin

   Info ("Sym_UN_Hanlder: """
         & Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last)
         & """");

   Find_Union
     (Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
      Desc,
      Union_Def,
      Success);

   if not Success then
      return;
   end if;

   Insert_Declaration
     (Handler               => LI_Handler (Global_CPP_Handler),
      File                  => Global_LI_File,
      List                  => Global_LI_File_List,
      Symbol_Name           =>
        Sym.Buffer (Sym.Identifier.First .. Sym.Identifier.Last),
      Source_Filename       =>
        Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
      Location              => Sym.Start_Position,
      Kind                  => Record_Type,
      Scope                 => Global_Scope,
      End_Of_Scope_Location => Union_Def.End_Position,
      Declaration_Info      => Decl_Info);

   Insert_Reference
     (Declaration_Info      => Decl_Info,
      File                  => Global_LI_File,
      Source_Filename       =>
        Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
      Location              => Union_Def.End_Position,
      Kind                  => End_Of_Spec);

   Free (Desc);
   Free (Union_Def);
end Sym_UN_Handler;
