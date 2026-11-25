# MaeShare client for Maemo 5 (Nokia N900): build, check the translations, package, deploy.
#
#   make help            this list
#   make                 build build/maeshare (needs a Qt 4.7 cross toolchain, see the variables)
#   make i18n-check      all language tables of qml/i18n.js have the same keys and placeholders, and every Chinese message of transfer.h is translated (needs node)
#   make deb             package: build/maeshare_$(VERSION)-$(REV)_armel.deb (needs BASE_DEB, dpkg-deb)
#   make deploy          copy the program and the QML files to the phone (DEVICE=root@address)
#   make clean
#
# Typical call with a Fremantle SDK sysroot (Qt 4.7 headers and libraries inside) and a cross compiler whose link step knows that sysroot:
#   make CXX=/path/to/arm-linux-gnueabi-g++ SYSROOT=/path/to/sysroot MOC=/path/to/moc-4.7 QJSON=/path/to/MeeGo-Share/third_party/qjson
# The moc must be the one of Qt 4.7 (the output of Qt 4.8 or 5 does not fit): the moc of the SDK is an i386 scratchbox program, it can be built from the Qt 4.7.4
# sources (qmake, src/tools/bootstrap, src/tools/moc).
#
# What is not built here: the helper `probe` (LocalSend network core; the source is not published, see NOTICE), the alias word lists and the sharing plugin.
# `make deb` takes them from the release package of the author (BASE_DEB, github.com/balancechiang/MaeShare/releases).

APP      := src/app
QML      := $(APP)/qml
OUT      ?= build
VERSION  ?= 1.0.3
REV      ?= 1maemo1

CXX      ?= arm-linux-gnueabi-g++
SYSROOT  ?=
MOC      ?= moc
MOC_CMD   = $(if $(findstring /,$(MOC)),$(abspath $(MOC)),$(MOC))
QJSON    ?= third_party/qjson
NODE     ?= node
STRIP    ?= $(subst g++,strip,$(CXX))

QT_INC   := $(SYSROOT)/usr/include
CXXFLAGS ?= -O2 -fPIC -fpermissive -w -DQT_NO_DEBUG
INCS     := -I$(QT_INC) -I$(QT_INC)/QtCore -I$(QT_INC)/QtGui -I$(QT_INC)/QtNetwork -I$(QT_INC)/QtDeclarative -I$(QT_INC)/QtScript -I$(QT_INC)/QtXml -I$(QJSON) -I$(OUT)/gen
DEFS     := -DQT_NETWORK_LIB -DQT_GUI_LIB -DQT_CORE_LIB -DQT_DECLARATIVE_LIB
LIBS     := -L$(SYSROOT)/usr/lib -lQtDeclarative -lQtGui -lQtNetwork -lQtCore -lm

QJSON_SRC := parser.cpp json_scanner.cpp json_parser.cc serializer.cpp
OBJS      := $(OUT)/obj/app.o $(OUT)/obj/moc_transfer.o $(OUT)/obj/moc_singleinstance.o $(addprefix $(OUT)/obj/qjson_,$(addsuffix .o,$(basename $(QJSON_SRC))))

# phone
DEVICE   ?=
SSH_OPTS ?= -o ConnectTimeout=12

.PHONY: all help i18n-check deb deploy clean
all: $(OUT)/maeshare

help:
	@sed -n '2,12p' Makefile

# moc writes the path of the header into its output: the headers are copied next to the output and moc runs there
$(OUT)/gen/%.h: $(APP)/%.h
	@mkdir -p $(OUT)/gen && cp $< $@
$(OUT)/gen/moc_%.cpp: $(OUT)/gen/%.h
	cd $(OUT)/gen && $(MOC_CMD) $*.h -o moc_$*.cpp

$(OUT)/obj/app.o: $(APP)/app.cpp $(OUT)/gen/transfer.h $(OUT)/gen/singleinstance.h
	@mkdir -p $(OUT)/obj
	$(CXX) $(CXXFLAGS) $(DEFS) $(INCS) -c $< -o $@
$(OUT)/obj/moc_%.o: $(OUT)/gen/moc_%.cpp
	@mkdir -p $(OUT)/obj
	$(CXX) $(CXXFLAGS) $(DEFS) $(INCS) -c $< -o $@
$(OUT)/obj/qjson_%.o:
	@mkdir -p $(OUT)/obj
	$(CXX) $(CXXFLAGS) $(DEFS) $(INCS) -c $(firstword $(wildcard $(QJSON)/$*.cpp $(QJSON)/$*.cc)) -o $@

$(OUT)/maeshare: $(OBJS)
	$(CXX) $(OBJS) -o $@ $(LIBS)
	-$(STRIP) --strip-unneeded $@
	@ls -l $@

i18n-check:
	$(NODE) tools/i18n-check.js

BASE_DEB ?=
deb: $(OUT)/maeshare
	@test -n "$(BASE_DEB)" || { echo "Set BASE_DEB=path/to/maeshare_$(VERSION)_armel.deb (the release of the author)"; exit 1; }
	tools/make-deb.sh "$(BASE_DEB)" $(OUT)/maeshare $(QML) $(OUT) $(VERSION) $(REV)

deploy: $(OUT)/maeshare
	@test -n "$(DEVICE)" || { echo "Set DEVICE=root@address of the phone"; exit 1; }
	scp -O $(SSH_OPTS) $(OUT)/maeshare $(DEVICE):/opt/maeshare/maeshare.new
	scp -O $(SSH_OPTS) $(QML)/*.qml $(QML)/i18n.js $(DEVICE):/opt/maeshare/
	ssh $(SSH_OPTS) $(DEVICE) 'cd /opt/maeshare && mv -f maeshare.new maeshare && chmod 755 maeshare && mkdir -p qml47 && cp i18n.js qml47/ && for f in *.qml; do sed "s/^import QtQuick 1\.0\$$/import Qt 4.7/" $$f > qml47/$$f; done; echo deployed: restart the application'

clean:
	rm -rf $(OUT)
