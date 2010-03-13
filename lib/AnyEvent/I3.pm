package AnyEvent::I3;
# vim:ts=4:sw=4:expandtab

use strict;
use warnings;
use JSON::XS;
use AnyEvent::Handle;
use AnyEvent::Socket;
use AnyEvent;

=head1 NAME

AnyEvent::I3 - communicate with the i3 window manager

=cut

our $VERSION = '0.01';

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

This module connects to the i3 window manager using the UNIX socket based
IPC interface it provides (if enabled in the configuration file). You can
then subscribe to events or send messages and receive their replies.

Note that as soon as you subscribe to some kind of event, you should B<NOT>
send any more messages as race conditions might occur. Instead, open another
connection for that.

    use AnyEvent::I3;

    my $i3 = i3("/tmp/i3-ipc.sock");

    $i3->connect->recv;
    say "Connected to i3";

    my $workspaces = $i3->message(1)->recv;
    say "Currently, you use " . @{$workspaces} . " workspaces";

=head1 EXPORT

=head2 $i3 = i3([ $path ]);

Creates a new C<AnyEvent::I3> object and returns it. C<path> is the path of
the UNIX socket to connect to.

=head1 SUBROUTINES/METHODS

=cut


use Exporter;
use base 'Exporter';

our @EXPORT = qw(i3);


my $magic = "i3-ipc";

# TODO: export constants for message types
# TODO: auto-generate this from the header file? (i3/ipc.h)
my $event_mask = (1 << 31);
my %events = (
    workspace => ($event_mask | 0),
);

sub _bytelength {
    my ($scalar) = @_;
    use bytes;
    length($scalar)
}

sub i3 {
    AnyEvent::I3->new(@_)
}

=head2 $i3 = AnyEvent::I3->new([ $path ])

Creates a new C<AnyEvent::I3> object and returns it. C<path> is the path of
the UNIX socket to connect to.

=cut
sub new {
    my ($class, $path) = @_;

    $path ||= '/tmp/i3-ipc.sock';

    bless { path => $path } => $class;
}

=head2 $i3->connect

Establishes the connection to i3. Returns an C<AnyEvent::CondVar> which will
be triggered with a boolean (true if the connection was established) as soon as
the connection has been established.

    if ($i3->connect->recv) {
        say "Connected to i3";
    }

=cut
sub connect {
    my ($self) = @_;
    my $hdl;
    my $cv = AnyEvent->condvar;

    tcp_connect "unix/", $self->{path}, sub {
        my ($fh) = @_;

        return $cv->send(0) unless $fh;

        $self->{ipchdl} = AnyEvent::Handle->new(
            fh => $fh,
            on_read => sub { my ($hdl) = @_; $self->_data_available($hdl) }
        );

        $cv->send(1)
    };

    $cv
}

sub _data_available {
    my ($self, $hdl) = @_;

    $hdl->unshift_read(
        chunk => length($magic) + 4 + 4,
        sub {
            my $header = $_[1];
            # Unpack message length and read the payload
            my ($len, $type) = unpack("LL", substr($header, length($magic)));
            $hdl->unshift_read(
                chunk => $len,
                sub { $self->_handle_i3_message($type, $_[1]) }
            );
        }
    );
}

sub _handle_i3_message {
    my ($self, $type, $payload) = @_;

    return unless defined($self->{callbacks}->{$type});

    my $cb = $self->{callbacks}->{$type};
    $cb->(decode_json $payload);
}

=head2 $i3->subscribe(\%callbacks)

Subscribes to the given event types. This function awaits a hashref with the
key being the name of the event and the value being a callback.

    $i3->subscribe({
        workspace => sub { say "Workspaces changed" }
    });

=cut
sub subscribe {
    my ($self, $callbacks) = @_;

    my $payload = encode_json [ keys %{$callbacks} ];
    my $message = $magic . pack("LL", _bytelength($payload), 2) . $payload;
    $self->{ipchdl}->push_write($message);

    # Register callbacks for each message type
    for my $key (keys %{$callbacks}) {
        my $type = $events{$key};
        $self->{callbacks}->{$type} = $callbacks->{$key};
    }
}

=head2 $i3->message($type, $content)

Sends a message of the specified C<type> to i3, possibly containing the data
structure C<payload>, if specified.

    my $cv = $i3->message(0, "reload");
    my $reply = $cv->recv;
    if ($reply->{success}) {
        say "Configuration successfully reloaded";
    }

=cut
sub message {
    my ($self, $type, $content) = @_;

    die "No message type specified" unless $type;

    my $payload = "";
    if ($content) {
        if (ref($content) eq "SCALAR") {
            $payload = $content;
        } else {
            $payload = encode_json $content;
        }
    }
    my $message = $magic . pack("LL", _bytelength($payload), $type) . $payload;
    $self->{ipchdl}->push_write($message);

    my $cv = AnyEvent->condvar;

    # We don’t preserve the old callback as it makes no sense to
    # have a callback on message reply types (only on events)
    $self->{callbacks}->{$type} =
        sub {
            my ($reply) = @_;
            $cv->send($reply);
            undef $self->{callbacks}->{$type};
        };

    $cv
}

=head1 AUTHOR

Michael Stapelberg, C<< <michael at stapelberg.de> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-anyevent-i3 at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=AnyEvent-I3>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc AnyEvent::I3

You can also look for information at:

=over 2

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=AnyEvent-I3>

=item * The i3 window manager website

L<http://i3.zekjur.net/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 Michael Stapelberg.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of AnyEvent::I3
