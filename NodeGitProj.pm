#package NodeProject;
package NodeGitProj;
use strict;
use warnings;
use Data::Dumper; # CORE
# use JSON::XS; # libjson-xs-perl
use JSON; # libjson-perl (libjson-pp-perl)
# use SemVer; # Debian: libsemver-perl (Not in use yet)

use Mail::Sendmail; # libmail-sendmail-perl
use Date::ISO8601;  # libdate-iso8601-perl
use Sys::Hostname; # CORE
use Cwd; # CORE
use File::Find; # CORE

our $VERSION = '0.1.2';
# my $appcfgfname = "$appid.conf.json";

=head1 NAME

NodeGitProj - Manage the Deployment lifecycle of Git Stored Node.js App.

=head1 SYNOPSIS

    use NodeGitProj;
    my $ver = "0.1.0";
    eval {
      $np = NodeGitProj->new('conf' => "/path/to/package.json");
      $np->deploytag($ver);
      $np->deps_install();
      $np->db_migrate();
      $np->server_restart();
      $np->inform("Ver. $ver Deployed");
    };
    if ($@) {die("Failed to deploy ...");}

=head1 DESCRIPTION

NodeGitProj utilizes the Node Project package.json file and the wealth of
information embedded in it to make Node application deployment easy and
automated.
You can use NodeGitProj on the module / API level or use the shipped
command line tool to run the deployment steps.

=head2 CONFIG VARIABLES USED FROM package.json

=over 4

=item * name - for looking up additional app specific config file for the app

=item * description - for naming the app in informative messages and email

=item * main - executable for starting / restarting the app server

=item * version - string for tagging the release version

=item * contributors - for sending email on release deployment

=item * devDependencies - for seeing what process manager Node app might use

=back

=head2 CONFIG OVERRIDES

Some settings related to tasks that NodeGitProj carries out are not easily presented (especially in standard)
package.json file. For these things environment variables are used

    NODEGIT_FROM - Sender email address for the deployment email notifications.

These variables are best mainatained in a local shell config file (e.g. ~/.bashrc)

=head2 $np->lastver()

Get the last / latest version (by alphabetical sorting order which is
NOT exactly same as Semantic versioning sorting order - a round of custom
sorting may need to be applied to achieve semver order).

=cut
sub lastver {
   my ($cfg) = @_;
   if (!@{$cfg->{'tags'}}) {
      # Extract versions from Git, brute force
      $cfg->gettags();
   }
   my $li = scalar(@{$cfg->{'tags'}}) - 1;
   # print(STDERR "li: $li\n");
   return $cfg->{'tags'}->[$li];
}

=head2 NodeGitProj::taglbl()

Create a semver-compatible (See: http://semver.org/) version tag string (not a Git tag, but only name)
to use for Git tagging purposes.
Allow package.json (non-standard) member "rc" to affect tag formation.
If the "rc" field in package.json is set to 0 or not present, the tag label
will always equate the "version" field of package.json.

=cut
sub taglbl {
   my ($cfg) = @_;
   my $lbl = $cfg->{'version'};
   my @comps;
   # TODO: Try various prefixes, 'rc', 'beta','alpha'
   if (my $rc = $cfg->{'rc'}) {
      print(STDERR "rc: $rc\n");
      if ($rc =~ /\./) {@comps = split(/\./, $rc);}
      elsif ($rc !~ /^\d+$/) {die("rc part does not look like a number (!)");}
      else {
        @comps = split(//, $rc);
        if (@comps == 1) {unshift(@comps, 0);}
        
      }
      if (@comps != 2) {die("rc (release candidate) part only supports 2 digits - in either 2 digit dot-notation or 1-2 digit decimal.");}
      # Lets make the tag semver compliant !
      $lbl .= "-rc.".join('.', @comps);
   }
   return($lbl);
}

=head2 $np = NodeGitProj->new(%opts);

Construct NodeProject Object by parsing local package.json.
The structure of Object is fundamentally same as format of NPM
package.json file.
(Read more on: https://docs.npmjs.com/files/package.json).
Keyword params in %opts:

=over 4

=item * conf - Full custom (absolute) path to package.json (default "./package.json")
    
=item * appconf - Application Custom config file (with member 'staticroot' to
hint where SPA app static content root / docroot is located).

=back

Exceptions ar thrown on any errors during construction (package.json not found,
JSON wrongly formatted, ...).

=cut
sub new {
  my ($class, %c) = @_;
  my @t = localtime(time());
  #DEBUG:print(Dumper(\@t));
  my $debug = $ENV{'DEPLOY_DEBUG'} || 0;
  my $iso = Date::ISO8601::present_ymd($t[5]+1900, $t[4]+1, $t[3]);
  #DEBUG: print("Date: $iso\n");
  my $cfgfname = $c{'conf'} || "package.json"; # PKG var ...
  if ( ! -f $cfgfname) {die("No '$cfgfname' found (pass in 'conf' if not in current dir)!");}
  # TODO: Eliminate the dirty backtick op.
  my $cont = `cat $cfgfname`;
  $cont =~ s/\r//g;
  my $cfg = decode_json($cont);
  my $vernew =  $cfg->{'version'};
  $cfg->{'date'} = $iso;
  # Release candidate (0 => ignore rc, this is an actual release)
  $cfg->{'rc'}  =  $cfg->{'rc'} || 0;
  $cfg->{'debug'} = $debug;
  # `git status package.json`;
  bless($cfg, $class); # , 'NodeProject'
  #print(Dumper($cfg));
  my @tags = $cfg->gettags();
  # Load application custom JSON config by app id / basename in 'name'.
  # TODO:
  # - Try this from base directory of package.json
  # - Allow overriding in %opts
  my $appconf = $c{'appconf'} ? "$c{'appconf'}" : "./$cfg->{'name'}.conf.json";
  print(STDERR "Found appconfig: $appconf\n");
  if (-f $appconf) {
    my $cc = `cat $appconf`; # Config content
    $cc =~ s/\r//g;
    my $appcfg = decode_json($cc);
    $cfg->{'appcfg'} = $appcfg;
  }
  return($cfg);
}
# Test if the new version
sub newversiongood {
  my ($vernew, $verlast) = @_;
  # New must be bigger and different
  if ( ($vernew cmp $verlast) <= 0) {
    die("Version sequence Messed up: new: $vernew cmp last: $verlast\n");
  }
}

=head2 $np->gettags()

Fetch tags (or refetch them after a change) and register them in Project
instance for later use.
Use may include overlap comparisons, providing a list of tags in UI etc.

=cut
sub gettags {
  my ($cfg) = @_;
  my @tags = `git tag`;
  @tags = map({s/\s+//;/^\d+\.\d+\.\d+.*$/ ? $_ : ();} @tags);
  if ($cfg) {$cfg->{'tags'} = \@tags;}
  local $Data::Dumper::Indent = 0;
  if ($cfg->{'debug'}) { DEBUG:print("Tags:".Dumper(\@tags)."\n"); }
  return(@tags);
}

=head2 NodeGitProj::createtag($vertag)

Class method to create tag (in Git local repo, storing it to remote
is a separate step, see storetag())

=cut
sub createtag {
   my ($ver, $msg) = @_;
   if ($ver =~ /\s/) {die("Version has spaces in it !");} # - fix to preceed
   if ($msg =~ /\"/) {die("Message cannot have quotes !");}
   my $cmd = "git tag -a $ver -m \"$msg\"";
   print(STDERR "Tag by command: $cmd\n");
   my $out = `$cmd`;
   if ($?) {die("Git Tagging failed: $out");}
   print(STDERR "Tagged with $ver\n");
}

=head2 NodeGitProj::storetag()

Class method to Store (push) tag into Git VC.

=cut
sub storetag {
   #my () = @_;
   # Check that no uncommitted files remain (?)
   #my $cmd2 = 'git push --tags';
   # Do we need "git checkout master" here (to ensure we are **really** in master and will not have any tag related quirks)
   my $coout = `git checkout master`; # system() # TEST by first being in a tag !!!
   # Had to add "origin master" (or is this necessary)
   my $cmd = 'git push origin master --follow-tags';
   my $out = `$cmd`;
   if ($?) {die("Pushing tags (by: $cmd) failed: $out");}
   print(STDERR "Pushed (all) tag(s)\n");
}

=head2 $np->deploytag($vertag)

Deploy a tag by fetching all available tags from remote (by "git fetch").
Passing no $vertag skips the checkout (fetch is still done w/o version).

Throw exceptions on failing fetch or checkout.

=cut
sub deploytag {
   my ($cfg, $ver, %c) =@_;
   if (!$ver) {$ver = '';} # just to be defined (for strict)
   my $currver = $cfg->{'version'};
   # Should not affect 'master' deployment
   if ($ver && !$c{'force'} && ($ver eq $cfg->taglbl())) {
      die("Tag to Deploy seems to be same as one for current deployment. Use 'force' to override.");
      return;
   }
   # fetch --all would mean "all remotes" (however consider --force with fetch)
   my @cmds = ("git fetch", "git checkout --force tags/$ver");
   #print(STDERR "Run following in the deployment env:\n");
   #for my $c (@cmds) {
   #   print(STDERR "$c\n");
   #}
   # FETCH ! NOTE: This does not seem to get(fetch ?) 'master' branch (!!) "git pull origin master" does !
   my $out = `$cmds[0]`;
   print(STDERR "Fetch branch/tag ''by cmd: $cmds[0]\n");
   if ($?) { die("Git Fetch failed: $out"); }
   # Query tags (again)
   my @tags = $cfg->gettags();
   # Allow intentionally to skip checkout (by passing no version)
   if (!$ver ) {return;} # || $c{'noco'}
   # Consider "master" as special version tag
   if ($ver eq 'master') { $cmds[1] = "git checkout master";}
   elsif (!grep({$_ eq $ver;} @tags)) {die("Version tag '$ver' not available (Tags: @tags)");}
   print(STDERR "Checking out by: $cmds[1]\n");
   $out = `$cmds[1]`;
   if ($?) {die("Git Checkout (of $ver) failed: $out");}
   1;
}

=head2 $np->server_restart()

Restart (Node) Application server using one of popular Node process managers.
The process manager is looked up from package.json "devDependencies", looking
for "pm2" and "forever" in that order.
Typically this is done after deployment. Lookup package.json member
'main' for the app main executable.

=cut
# TODO: Find
sub server_restart {
   my ($cfg) = @_;
   # Look at devDependencies
   # NEW: Do not mandate to have
   #if (`which pm2` && $?) {die("pm2 utility not installed");}
   my $dd = $cfg->{'devDependencies'};
   my @pms = ('pm2','forever'); # Supported process managers
   my $pm = '';
   my @mypms = map({$dd->{$_} ? $_ : ();} @pms); # Find pm in use
   if ( ! @mypms) { print(STDERR "no process manager (@pms) listed as dev.dep."); return; }
   $pm = shift(@mypms);
   # Whatever  supported by particular pm (status N/A on forever, use list)
   my %pmops_bypm = (
     'pm2' => ["status","stop","start","status"],
     'forever' => ["list","stop","start","list"]); # 
   #OLD: my @pmops = ("stop","start");
   my @pmops = @{$pmops_bypm{$pm}};
   print(STDERR "Call: @pmops\n");
   my @cmds = map({"$pm $_ $cfg->{'main'}";} @pmops);
   my $delay = 1;
   my $i = 0;
   for (@cmds) {
     system($_);
     if ($pmops[$i] eq 'stop') {$i++;next;} # Ignore exit value
     $i++;
     #$delay *= 2;
     if ($?) {die("Failed: $_\n");}
     #sleep($delay);
   }
}

=head2 $np->inform($subj, $body)

Inform people registered as 'contributors' in package.json by an email.
If left out the $subj and $body are defaulted to informative values conveying
the appname, version, time of deployment and user identity of deploying
OS user.

=cut
sub inform {
   my ($cfg, $title, $body) = @_;
   my $clist = $cfg->{'contributors'};
   if (!$clist || !@$clist) {return;}
   my @mlist = map({ $_->{'email'}; } @$clist);
   # NEW: Formulate default messages
   my $host = hostname();
   my $ver = $cfg->taglbl();
   $title = $title || "$cfg->{'description'} Version '$ver' Deployed";
   $body  = $body  || "Deployed on $cfg->{'date'} by $ENV{'USER'}\@$host";
   # Figure out SMTP From: Address
   my $from = $cfg->emailfrom() || "$ENV{'USER'}\@someplace.com";
   # TODO: Make swe
   my $mail = {
     To => join(';', @mlist),
     From => $from,
     Subject => $title,
     Message => $body,
   };
   sendmail(%$mail) or die $Mail::Sendmail::error;
}

# Look for Deployment mail sender (SMTP "From:" field) from variety of config locations.
sub emailfrom {
   my ($cfg) = @_;
   my $clist = $cfg->{'contributors'};
   # Email directly in %ENV
   if (my $f = $ENV{'NODEGIT_FROM'}) {return($f);}
   # ENV: Index to contributor list
   elsif (my $i = $ENV{'NODEGIT_FROM_IDX'}) {
     
     if (($i+1) > scalar(@$clist)) {die("Index to contributors is exceeding list boundaries !");}
     return($clist->[$i]->{'email'});
   }
   # In package.json "config" Object "emailfrom"
   elsif (my $f2 = $cfg->{'config'}->{'emailfrom'}) {return($f2);}
   elsif (ref($cfg->{'author'}) eq 'HASH') { return($cfg->{'author'}->{'email'}); }
   # Try first of 'contributors' ? Or one at idx
   elsif (ref($clist->[0]) eq 'HASH') {}
   # Exhauseted all options !
   return '';
}

=head2 $np->deps_install()

Install or update NPM and Bower dependencies.
Resolve document root for application for Bower installation part.

=cut
sub deps_install {
  my ($cfg, $docroot) = @_;
  #DEBUG:print(Dumper($cfg));
  # Find out docroot
  if ($docroot) {} # Explicit docroot passed - No probing actions
  elsif (my $sr = $cfg->{'appcfg'}->{'staticroot'}) {
     print(STDERR "docroot(appcfg): $sr\n");
     # Current dir + staticroot value
     $docroot = "./$sr";
  }
  else { $docroot = "./"; }
  # Ensure docroot exists
  if (! -d $docroot) {die("No static content root found ('$docroot')");}
  # Ensure docroot has bower.json and "bower_components"
  if (! -f "$docroot/bower.json") {die("No bower.json found");}
  if (! -d "$docroot/bower_components") {die("No 'bower_components' in docroot !");}
  # NPM
  # Must have existing "node_modules" (makes this not valid for first time install)
  if (-d "./node_modules") { `npm install`; }
  # Bower
  my $cwd = getcwd();
  chdir($docroot);
  `bower install`;
  chdir($cwd);
  #if ($?) {print(STDERR "Error from Bower Install (in '$docroot'): $?");}
}

=head2 $np->db_migrate()

Migrate Database Schema.
Evolutionary migrate database schema based on Sequelize migrations.

=cut
sub db_migrate {
  my ($cfg) = @_;
  # Ensure sequelize cli is installed 
  if (!-e '/usr/bin/sequelize') {die("No sequelize cli found");}
  # Sequelize migrate
  `sequelize db:migrate`;
}

=head2 $np->deps_check();

Provide a superficial dependency version check of NPM packages.
Iterate through dependencies in package.json and look them up in (their respective installation directories in) the filesystem.

=cut
sub deps_check {
  my ($cfg, $opts) = @_;
  my $modpath = "./node_modules";
  if ( ! -d $modpath ) { die("No module path '$modpath'"); }
  #print(Dumper($cfg));
  my $deps = $cfg->{'dependencies'};
  if (!$deps || (keys(%$deps) < 1)) { die ("No dependencies"); }
  my @deps = ();
  for my $k (keys(%{$deps})) {
	my $cmp = '';
	my $ver = '';
	if ($deps->{$k} !~ /^\D?\d+\.\d+\.\d+$/) { 
	  #print("Non-digit: deps->{$k}\n");
	  $ver = '';
	}
	#if ($deps->{$k} !~ /^(\D)(\d+\.){3}$/) {}
	elsif ($deps->{$k} =~ s/^(\D)?//) { $cmp = $1; $ver = $deps->{$k}; };
	# else {}
	#print("$k => $deps->{$k} (CMP: $cmp)\n");
	my $modinfo = { "id" => $k, "ver" => $ver };
	if ($cmp) { $modinfo->{'cmp'} = $cmp; }
	push(@deps, $modinfo);
  }
  #print(Dumper(\@deps));
  for my $mi (@deps) {
	 if (!-d "$modpath/$mi->{'id'}") { push(@{$mi->{'errors'}}, "Missing module dir"); next; }
	 if (!-f "$modpath/$mi->{'id'}/package.json") { push(@{$mi->{'errors'}}, "Missing module package.json"); next; }
	 my $cont = `cat $modpath/$mi->{'id'}/package.json`;
	 my $pkg = decode_json($cont);
	 #print(Dumper($pkg));
	 if ($pkg->{'name'}    ne $mi->{'id'})  { push(@{$mi->{'errors'}}, "Non-matching module id ($pkg->{'name'} vs. $mi->{'id'})"); }
	 if ($mi->{'ver'} && ($pkg->{'version'} ne $mi->{'ver'})) { push(@{$mi->{'errors'}}, "Non-matching module version ($pkg->{'version'} vs. $mi->{'ver'})"); }
	 
  }
  #print(Dumper(\@deps));
  my $onlyerrors = $opts->{onlyerrors};
  if ($onlyerrors) { @deps = grep({ $_->{'errors'}; } @deps); }
  return(\@deps);
}
my @codefiles = ();
my $codefiles_patt = '';
# File::Find callback for finding code files (by $codefiles_patt)
sub fstree_process {
  my ($foo) = @_;
  #print("$File::Find::name\n");
  if ($File::Find::name =~ /\.$codefiles_patt$/) { push(@codefiles, $File::Find::name); }
}
sub parselintreport {
  my ($infostr) = @_;
  my @lines = split (/\n/, $infostr);
  #m y $len = scalar(@lines); # Number of items - redundant with negative offset
  splice (@lines, -2);
  #print (Dumper(\@lines));
  my @report = ();
  foreach my $line (@lines) {
	  $line =~ s/[^:]:\s*//; # Get rid of filename
	  my @errarr = split (/,\s*/, $line, 3);
	  my $err = {msg => $errarr[2]};
	  if ($errarr[0] =~ m/line\s*(\d+)/) { $err->{line} = int($1); }
	  if ($errarr[1] =~ m/col\s*(\d+)/)  { $err->{col}  = int($1); }
	  push (@report, $err);
  }
  return (\@report);
}
# TODO: How do we know where *application code* (not dependencies) reside
# export NODEGIT_APPCODE_PATH="./sjs:./bms:./utils:./devutil:./client/app:./client/components:./client/js:"
# export NODEGIT_LINTER=jshint
# export NODEGIT_LINTMAX=5
# export NODEGIT_CODEFILE_PATT="js|json"
# export NODEGIT_LINT_VCINFO=1
sub lint {
  my ($cfg, $opts) = @_; #  
  $codefiles_patt = 'js|json'; # Default
  my @path =  split(/:/, $ENV{'NODEGIT_APPCODE_PATH'});
  if (!@path) { die("No NODEGIT_APPCODE_PATH in env ! (Set to paths from where you want to lint the files)"); }
  my $lint = $ENV{'NODEGIT_LINTER'};
  if (!$lint) { die("No NODEGIT_LINTER in env ! (Set to linter executable)"); }
  my $lintmax = $ENV{'NODEGIT_LINTMAX'} ? int($ENV{'NODEGIT_LINTMAX'}) : 0;
  if ($ENV{'NODEGIT_CODEFILE_PATT'}) { $codefiles_patt = $ENV{'NODEGIT_CODEFILE_PATT'}; }
  print(STDERR "Searching code from path: ".Dumper(\@path));
  # TODO: Check presence of directories ...
  
  # follow_fast
  File::Find::find({ wanted => \&fstree_process, follow => 0, no_chdir => 1}, @path);
  print(STDERR scalar(@codefiles)." files to analyze\n");
  #print(Dumper(\@codefiles));
  my @filereports = ();
  my $i = 0;
  my $vcinfo = $ENV{'NODEGIT_LINT_VCINFO'} || $opts->{'vcinfo'} || 0; # Add info from VC
  foreach my $fn (@codefiles) {
	print(STDERR "$i) $fn\n"); # .$info
	my $lis = $vcinfo ? lineinfo($fn) : []; # Info from vc
	
	my $info = `$lint $fn`;
	$i++;
	if (!$info) { next; }
	
	if ($lintmax && ($i > $lintmax)) { last; }
	my $rep = { "filename" => $fn }; # "info" => $info
	$info = $rep->{'info'} = parselintreport($info);
	if ($vcinfo) { xclate($info, $lis); }
	push(@filereports, $rep); 
  }
  #print(Dumper(\@filereports));
  return \@filereports;
}

sub xclate {
  my ($info, $lis) = @_;
  foreach my $ei (@$info) {
	my $li = $lis->[ $ei->{'line'} - 1 ];
	@$ei{'author','datetime'} = @$li{'author','datetime'};
  }
}
# Keep this to Git-only or support SVN as well ?
sub lineinfo {
  my ($fname) = @_;
  #print(STDERR "File: $fname\n");
  # Inquiry version control type here (.git ? .svn ?). TODO: In more global place
  #my @vctypes = ('git','svn'); # Luckily these happen to be VC executable names too
  my $vctype = "git";
  #for (@vctypes) { if (-d "./.$_") { $vctype = $_; last; } }
  my @info = `$vctype blame $fname`;
  if ($?) { return []; }
  @info = map({
	  # Note: single space match requirement before final (.+) / $3 breaks matching
	  #$_ =~ /^([^\(]+)\s+\(([^\)]+)\)(.+)$/; # Orig
	  $_ =~ /^([^\(]+)\(([^\)]+)\)(.+)$/; # More versatile pattern for filename appearing in output for a file with rename history
	  # Add'l note: try to lock closing to \d+\) - capture \d+
	  my $i = {"hash" => $1,  "linecont" => $3}; # info => $2,
	  # Test if "hash" above has \s - likely sign of filename
	  my @subinfo = split(/\s+/, $2);
	  # Sample problem line:
	  # 2d14e4e6 (ZZZZ Service account (P) 2015-06-29 22:46:00 -0700  4) var sys = require('sys');
	  # d3795ce2 rackview.js           ((no author)     2015-04-14 02:37:35 +0000   3) /** @file
	  $i->{'lineno'}   = int( pop(@subinfo) ); # Got "(P" ? ... Not numeric
	  # MUST Check that we have 3 items to remove
	  if (scalar(@subinfo) < 3) { }
	  else {
	    $i->{'datetime'} = join(' ', splice(@subinfo, -3));
	    $i->{'author'}   = join(' ', @subinfo);
      }
	  #print( Dumper($i) );
	  $i;
  } @info);
  return(\@info);
}
=head1 TODO

Utilize "scripts" and "config" sections of package.json more effectively.

=cut
1;
