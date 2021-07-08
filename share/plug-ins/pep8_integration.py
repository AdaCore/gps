"""
This is the python format checker plugin for GPS.
Its aim is to check indentation, style when:
 1 user stop editing
 2 before python script is saved
"""

import sys
import pycodestyle
import GPS
import colorschemes
from io import StringIO
from modules import Module


class Catch_Stdout(list):

    def __enter__(self):
        self._stdout = sys.stdout
        sys.stdout = self._stringio = StringIO()
        return self

    def __exit__(self, *args):
        self.extend(self._stringio.getvalue().splitlines())
        sys.stdout = self._stdout


class Pep8_Module(Module):

    def __format_check(self, file):
        """
           Check format using pycodestyle for python source codes
        """
        # only check python file
        if file.language() == "python":
            for m in GPS.Message.list(category="Pep8"):
                if m.get_file() == file:
                    m.remove()

            # is buffer opened yet
            buf = GPS.EditorBuffer.get(file=file, open=False)
            if buf is None:
                return

            # parse text in buffer and catches stdout
            s = buf.get_chars()
            pref = GPS.Preference("Src-Editor-Strip-Trailing-Blanks")
            if (pref.get() != "Never"):
                source = [i.rstrip(" ") + "\n" for i in s.splitlines()]
            else:
                source = [i + "\n" for i in s.splitlines()]

            with Catch_Stdout() as output:
                m = pycodestyle.Checker(filename=None, lines=source, report=False)
                m.check_all()

            for i in output:
                a = i.split(":")
                m = GPS.Message(category="Pep8",
                                file=GPS.EditorBuffer.get(file=file,
                                                          open=False).file(),
                                line=int(a[1]),
                                column=int(a[2]),
                                text=a[3],
                                show_in_locations=False)

                m.set_action("", "gps-emblem-build-warning", m.get_text())
                m.set_style(colorschemes.STYLE_WARNING, 1)

    # The followings are hooks:
    def setup(self):
        """
           When GPS start, if imported success:
           register hook for format checker
        """
        for e in GPS.EditorBuffer.list():
            self.__format_check(e.file())

    def file_edited(self, f):
        """
        When file is open, check the format
        """
        self.__format_check(f)

    def buffer_edited(self, f):
        """
        When user stop editing, check the format
        """
        self.__format_check(f)

    def on_file_saved(self, f):
        """
        When file is saved, check the format
        """
        self.__format_check(f)
