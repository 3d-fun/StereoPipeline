######################################################################
# Automatically generated by qmake (2.01a) Sat Sep 6 23:26:54 2008
######################################################################

VWDIR = /Users/mbroxton/projects/VisionWorkbench/trunk/build
BOOSTDIR = /opt/local

TEMPLATE = app
TARGET = 
DEPENDPATH += .
INCLUDEPATH += . $$VWDIR/include $$BOOSTDIR/include
LIBS += -L$$VWDIR/lib -lvw -lvwCore -lvwMath -lvwImage -lvwFileIO -L$$BOOSTDIR/lib
QT += opengl

# Input
HEADERS += MainWindow.h PreviewGLWidget.h InputWidget.h PreprocessWidget.h Noise.h 
SOURCES += main.cc MainWindow.cc PreviewGLWidget.cc InputWidget.cc PreprocessWidget.cc
