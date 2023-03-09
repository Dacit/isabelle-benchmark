from cx_Freeze import setup, Executable

# base="Win32GUI" should be used only for Windows GUI app
# base = "Win32GUI" if sys.platform == "win32" else None
base = None

setup(executables=[Executable("just_benchmark.py", base=base)])
