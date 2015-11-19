# NodeGitProj

Manage the Deployment lifecycle of Git Stored Node.js App.

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

