# NodeGitProj

Manage the Deployment lifecycle of Git Stored Node.js App.

# Installation

## Basic Perl-based Install

    # TODO: Perl cpan/cpanp(cpanplus)/cpanm(cpanminus) based install
    # Module is not yet in cpan - cannot install it from CPAN (!)
    cpanm JSON Mail::Sendmail Date::ISO8601
    cd /tmp
    git clone https://github.com/ohollmen/NodeGitProj-PM.git
    cd NodeGitProj-PM
    # Perl Makefile.PL install
    perl Makefile.PL
    make
    sudo make install
    

## Debian install
    
    # Install deps
    sudo apt-get install libjson-perl libmail-sendmail-perl libdate-iso8601-perl
    # Git Clone, cd, Run Perl Makefile.PL install process
    
## MacOSX/Brew Install

    # Use cpanminus to install
    sudo brew install cpanminus
    # Install dependencies
    sudo cpanm JSON Mail::Sendmail Date::ISO8601
    # Clone from Git (see above) ...
    # Run Perl install process
    perl Makefile.PL; make; sudo make install
    
# Quick Usage

Main command line use cases for module

    # Prep for tagged release
    # - Checks validity / availability of package.json "version" for a Git Tag
    # - Creates tag and pushes it to default remote
    # Default is a dryrun, use --exec to actually run
    nodegit relprep --exec

    # Deploy tag at the application server
    # - Fetches all available tags
    # - Checkout version tag passed as --version
    # - Restart App Server
    # - Inform project contributors / participants by email
    nodegit deploy --version 0.5.2-rc.1.8
    # Impatiently deploy master
    nodegit deploy --version master

# More Extensive documentation

See POD for more extensive documentation (perldoc NodeGitProj)

    # Quick review / no-hassle https clone
    git clone https://github.com/ohollmen/NodeGitProj-PM.git
    cd NodeGitProj-PM
    # Read some docs
    # ... for CL Utility
    perldoc ./bin/nodegit
    # ... for API (less likely)
    perldoc ./NodeGitProj.pm

