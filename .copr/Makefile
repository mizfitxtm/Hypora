# COPR builds the source RPM with `make -f .copr/Makefile srpm` (SCM build, "make srpm" method).
NAME := hypora
VERSION := $(shell rpmspec -q --qf '%{version}' hypora.spec 2>/dev/null || sed -n 's/^Version:[[:space:]]*//p' hypora.spec)

srpm:
	dnf -y install git-core rpm-build
	git archive --prefix=$(NAME)-$(VERSION)/ -o $(NAME)-$(VERSION).tar.gz HEAD
	rpmbuild -bs --define "_sourcedir $(CURDIR)" --define "_srcrpmdir $(outdir)" hypora.spec
