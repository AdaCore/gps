-----------------------------------------------------------------------
--                                                                   --
--                     Copyright (C) 2001                            --
--                          ACT-Europe                               --
--                                                                   --
-- This library is free software; you can redistribute it and/or     --
-- modify it under the terms of the GNU General Public               --
-- License as published by the Free Software Foundation; either      --
-- version 2 of the License, or (at your option) any later version.  --
--                                                                   --
-- This library is distributed in the hope that it will be useful,   --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of    --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details.                          --
--                                                                   --
-- You should have received a copy of the GNU General Public         --
-- License along with this library; if not, write to the             --
-- Free Software Foundation, Inc., 59 Temple Place - Suite 330,      --
-- Boston, MA 02111-1307, USA.                                       --
--                                                                   --
-- As a special exception, if other files instantiate generics from  --
-- this unit, or you link this unit with other files to produce an   --
-- executable, this  unit  does not  by itself cause  the resulting  --
-- executable to be covered by the GNU General Public License. This  --
-- exception does not however invalidate any other reasons why the   --
-- executable file  might be covered by the  GNU Public License.     --
-----------------------------------------------------------------------

package Browsers is

   type Browser_Type_Mask is mod 256;
   Dependency_Browser : constant Browser_Type_Mask;
   Class_Browser      : constant Browser_Type_Mask;
   Any_Browser        : constant Browser_Type_Mask;
   --  The various types of browsers supported in Glide2. Note that a specific
   --  browser might include objects from several types (if for instance it
   --  acts both as a class_browser and a dependency_browser).

private
   Dependency_Browser : constant Browser_Type_Mask := 1;
   Class_Browser      : constant Browser_Type_Mask := 2;
   Any_Browser        : constant Browser_Type_Mask :=
     Dependency_Browser or Class_Browser;

end Browsers;
