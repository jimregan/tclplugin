Name:           tclplugin
Version:        2.1
Release:        0.2.b1%{?dist}
Summary:        Tcl/Tk plug-in for NPAPI web browsers
License:        BSD
Group:          Applications/Internet
URL:            http://tcl.sourceforge.net/
Source0:        %{name}-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildRequires:  gcc
BuildRequires:  tcl-devel >= 8.4
BuildRequires:  tk-devel >= 8.4
BuildRequires:  xorg-x11-devel
Requires:       tcl >= 8.4
Requires:       tk >= 8.4
Requires:       mozilla >= 1.7

%define mozilladir %{_libdir}/mozilla-1.7

%description
The Tcl plug-in allows NPAPI web browsers to run Tcl/Tk applets.  This
package is linked to Fedora's Tcl and Tk libraries instead of embedding a
private Tcl 8.3 interpreter.

%prep
%setup -q

%build
make -f unix/Makefile.fc3 RPM_OPT_FLAGS="%{optflags}" \
    MOZILLA_DIR=%{mozilladir}

%install
rm -rf %{buildroot}
install -d %{buildroot}%{mozilladir}/plugins
install -m 0755 build-fc3/libtclp2.1.so \
    %{buildroot}%{mozilladir}/plugins/libtclp2.1.so
install -d %{buildroot}%{_libexecdir}/tclplugin
install -m 0755 build-fc3/tclshp2.1 \
    %{buildroot}%{_libexecdir}/tclplugin/tclshp2.1
install -d %{buildroot}%{mozilladir}/tclplug/2.1
cp -a plugin safetcl config \
    %{buildroot}%{mozilladir}/tclplug/2.1/
cp -a library %{buildroot}%{mozilladir}/tclplug/2.1/utils
ln -s %{_datadir}/tcl8.4 \
    %{buildroot}%{mozilladir}/tclplug/2.1/tcl
ln -s %{_datadir}/tk8.4 \
    %{buildroot}%{mozilladir}/tclplug/2.1/tk
echo 'set ::plugin(executable) {%{_libexecdir}/tclplugin/tclshp2.1}' >> \
    %{buildroot}%{mozilladir}/tclplug/2.1/plugin/installed.cfg
echo 'set ::plugin(sharedLibraryDir) {%{mozilladir}/plugins}' >> \
    %{buildroot}%{mozilladir}/tclplug/2.1/plugin/installed.cfg

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%doc README changes ChangeLog license.terms doc
%{mozilladir}/plugins/libtclp2.1.so
%{_libexecdir}/tclplugin/tclshp2.1
%{mozilladir}/tclplug

%changelog
* Mon Jul 27 2026 Tcl Plugin maintainers <tclplugin-core@lists.sourceforge.net> - 2.1-0.2.b1
- Install the complete runtime under the Fedora Core 3 Mozilla 1.7 tree.

* Mon Jul 27 2026 Tcl Plugin maintainers <tclplugin-core@lists.sourceforge.net> - 2.1-0.1.b1
- Build against the Fedora Core 3 Tcl/Tk 8.4 packages.
