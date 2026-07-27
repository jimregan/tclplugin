Name:           tclplugin
Version:        3.1
Release:        1%{?dist}
Summary:        Tcl/Tk plug-in for Mozilla web browsers
License:        BSD
Group:          Applications/Internet
URL:            http://www.tcl.tk/software/plugin/
Source0:        %{name}-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  tcl-devel >= 8.4.1
BuildRequires:  tk-devel >= 8.4.1
BuildRequires:  xorg-x11-devel
Requires:       mozilla >= 1.7
Requires:       tcl >= 8.4.1
Requires:       tk >= 8.4.1

%define mozilladir %{_libdir}/mozilla-1.7

%description
The Tcl/Tk browser plug-in allows NPAPI-compatible Mozilla browsers to run
Tcl applets.  Version 3.1 uses the installed Tcl and Tk 8.4 libraries through
the Tcl stubs interface.

%prep
%setup -q

%build
CFLAGS="%{optflags}" ./configure \
    --prefix=%{_prefix} \
    --exec-prefix=%{_exec_prefix} \
    --libdir=%{_libdir} \
    --with-tcl=%{_libdir} \
    --with-tk=%{_libdir} \
    --with-mozilla=%{mozilladir} \
    --enable-shared
make

%install
rm -rf %{buildroot}
make install DESTDIR=%{buildroot}

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%doc README ChangeLog changes license.terms doc
%{mozilladir}/plugins/*nptcl*.so
%{_libdir}/nptcl3.1

%changelog
* Mon Jul 27 2026 Tcl Plugin maintainers <tclplugin-core@lists.sourceforge.net> - 3.1-1
- Package the Tcl 8.4-compatible Plugin 3.1 sources for Fedora Core 3.
