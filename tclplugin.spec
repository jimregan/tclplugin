Name:           tclplugin
Version:        2.1
Release:        0.1.b1%{?dist}
Summary:        Tcl/Tk plug-in for NPAPI web browsers
License:        BSD
Group:          Applications/Internet
URL:            http://tcl.sourceforge.net/
Source0:        %{name}-%{version}.tar.gz
BuildRequires:  gcc
BuildRequires:  tcl-devel >= 8.4
BuildRequires:  tk-devel >= 8.4
BuildRequires:  xorg-x11-devel
Requires:       tcl >= 8.4
Requires:       tk >= 8.4

%description
The Tcl plug-in allows NPAPI web browsers to run Tcl/Tk applets.  This
package is linked to Fedora's Tcl and Tk libraries instead of embedding a
private Tcl 8.3 interpreter.

%prep
%setup -q

%build
make -f unix/Makefile.fc3 RPM_OPT_FLAGS="%{optflags}"

%install
rm -rf %{buildroot}
install -d %{buildroot}%{_libdir}/mozilla/plugins
install -m 0755 build-fc3/libtclp2.1.so \
    %{buildroot}%{_libdir}/mozilla/plugins/libtclp2.1.so
install -d %{buildroot}%{_libexecdir}/tclplugin
install -m 0755 build-fc3/tclshp2.1 \
    %{buildroot}%{_libexecdir}/tclplugin/tclshp2.1
install -d %{buildroot}%{_libdir}/mozilla/tclplug/2.1
cp -a plugin library safetcl config \
    %{buildroot}%{_libdir}/mozilla/tclplug/2.1/
echo 'set ::plugin(executable) {%{_libexecdir}/tclplugin/tclshp2.1}' >> \
    %{buildroot}%{_libdir}/mozilla/tclplug/2.1/plugin/installed.cfg
echo 'set ::plugin(sharedLibraryDir) {%{_libdir}/mozilla/plugins}' >> \
    %{buildroot}%{_libdir}/mozilla/tclplug/2.1/plugin/installed.cfg

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%doc README changes ChangeLog license.terms doc
%{_libdir}/mozilla/plugins/libtclp2.1.so
%{_libexecdir}/tclplugin/tclshp2.1
%{_libdir}/mozilla/tclplug

%changelog
* Mon Jul 27 2026 Tcl Plugin maintainers <tclplugin-core@lists.sourceforge.net> - 2.1-0.1.b1
- Build against the Fedora Core 3 Tcl/Tk 8.4 packages.
