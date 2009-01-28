package Perlbal::Plugin::ConfLoader;
use strict;
use warnings;
no  warnings qw(deprecated);

# called when we are loaded
sub load {
    my $class = shift;

    Perlbal::register_global_hook('manage_command.load_conf', sub {
        my $mc = shift->parse(qr/^load_conf\s+=\s+(.+)\s*$/,
              "usage: LOAD_CONF = <config files>");

        my ($glob) = $mc->args;

        # read conf files
        for (glob($glob)) {
            load_config($_, sub { print STDOUT "$_[0]\n"; });
        }
        return $mc->ok;
    });

    return 1;
}

sub load_config {
    my ($file, $writer) = @_;
    open (my $fh, $file) or die "Error opening config file ($file): $!\n";
    my $ctx = Perlbal::CommandContext->new;
    $ctx->verbose(0);
    while (my $line = <$fh>) {
        $line =~ s/\$(\w+)/$ENV{$1}/g;
        return 0 unless run_manage_command($line, $writer, $ctx);
    }
    close($fh);
    return 1;
}

# returns 1 if command succeeded, 0 otherwise
my $now_create_service;
sub run_manage_command {
    my ($cmd, $out, $ctx) = @_;  # $out is output stream closure

    $cmd =~ s/\#.*//;
    $cmd =~ s/^\s+//;
    $cmd =~ s/\s+$//;
    $cmd =~ s/\s+/ /g;

    my $orig = $cmd; # save original case for some commands
    $cmd =~ s/^([^=]+)/lc $1/e; # lowercase everything up to an =
    return 1 unless $cmd =~ /^\S/;

    # expand variables
    $cmd =~ s/\$\{(.+?)\}/_expand_config_var($1)/eg;

    $out ||= sub {};
    $ctx ||= Perlbal::CommandContext->new;

    my $err = sub {
        $out->("ERROR: $_[0]");
        return 0;
    };
    my $ok = sub {
        $out->("OK") if $ctx->verbose;
        return 1;
    };

    return $err->("invalid command") unless $cmd =~ /^(\w+)/;
    my $basecmd = $1;


    # for testing auto crashing and recovery:
    if ($basecmd eq "crash") { die "Intentional crash." };

    if ($now_create_service && $basecmd =~ /enable|set/i ) {
        if ($basecmd =~ /enable/) {
            $now_create_service = '';
        }
        return 1;
    } elsif ($now_create_service && $basecmd =~ /^vhost|group$/i ) {
        my @tmp = split /\s/, $cmd;
        $cmd = join ' ', $tmp[0], $now_create_service, @tmp[1..(scalar(@tmp)-1)];
    }
    
    # check already create service
    if ($basecmd eq 'create' && $orig =~ /CREATE SERVICE/i) {
        (my $show_cmd = $orig) =~ s/CREATE/SHOW/i;
        my $callback_msg;
        my $callback = sub {
            $callback_msg = $_[0] if $_[0] =~ /^SERVICE/;
        };
        Perlbal::run_manage_command($show_cmd, $callback);
        if ( $callback_msg && $callback_msg =~ /^SERVICE (.+)/ ) {
            $now_create_service = $1;
            return 1;
        }
    }

    my $mc = Perlbal::ManageCommand->new($basecmd, $cmd, $out, $ok, $err, $orig, $ctx);

    if (my $handler = Perlbal->can("MANAGE_$basecmd")) {
        my $rv = eval { $handler->($mc); };
        return $mc->err($@) if $@;
        return $rv;
    }

    # if no handler found, look for plugins

    # call any hooks if they've been defined
    my $rval = eval { Perlbal::run_global_hook("manage_command.$basecmd", $mc); };
    return $mc->err($@) if $@;
    if (defined $rval) {
        # commands may return boolean, or arrayref to mass-print
        if (ref $rval eq "ARRAY") {
            $mc->out($_) foreach @$rval;
            return 1;
        }
        return $rval;
    }

    return $mc->err("unknown command: $basecmd");
}

# called for a global unload
sub unload {
    # unregister our global hooks
    Perlbal::unregister_global_hook('manage_command.load_conf');
    return 1;
}

1;

=head1 NAME

Perlbal::Plugin::ConfLoader - load configuration files

=head1 SYNOPSIS

This module provides a Perlbal plugin which can be loaded and used as
follows:

    LOAD ConfLoader
    LOAD_CONF = /etc/perlbal/my.conf

You may also specify multiple configuration files a la File::Glob:

    LOAD_CONF = /foo/bar.conf /foo/quux/*.conf

=cut

