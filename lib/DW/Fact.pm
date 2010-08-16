package DW::Fact;

use warnings;
use strict;

use Carp;
use Data::Dumper;
use DBI;

use DW::Dimension;
use DW::Aggregate;

use List::MoreUtils qw/uniq/;

sub new {
    my ( $class, %params ) = @_;

    croak "Error: missing dbh or dsn" if !$params{dbh} and !$params{dsn};

    if ( $params{dsn} ) {
        $params{dbh} = DBI->connect( $params{dsn}, $params{db_user}, $params{db_password} );
    }

    bless {%params}, $class;
}

sub dimension {
    my ( $self, $dim_table ) = @_;

    return DW::Dimension->new(
        dbh  => $self->{dbh},
        name => $dim_table,
    );
}

sub aggregate {
    my ( $self, @dimensions ) = @_;

    return DW::Aggregate->new(
        dbh        => $self->{dbh},
        base_table => $self->{name},
        dimension  => \@dimensions,
    );
}

sub base_query {
    my ( $self, $dim_attr, $where ) = @_;

    # @dim_attr is a list of "table.columns"
    my $fact_table = $self->{name};
    my @dim_attr   = @{$dim_attr};
    my @dim_tables = uniq( map { ( split( /\./, $_ ) )[0] } @dim_attr );

    my $query = <<"SQL";
SELECT
    @{[ join(", ", @dim_attr) ]},
    SUM(n) AS n
FROM
    $fact_table
JOIN
@{[ join(",\n", map { $self->_join_str($_) } @dim_tables) ]}
GROUP BY
    @{[ join(", ", @dim_attr) ]}
SQL

    return $query;

    my $dbh = $self->{dbh};

    my $sth = $dbh->prepare($query);

    my $rv = $sth->execute() or die $dbh->errstr;

    return $sth->fetchall_arrayref();
}

sub aggr_query {
    my ( $self, $dim_attr, $where ) = @_;

    my $base_query = $self->base_query( $dim_attr, $where );

    my @dim_attr = @{$dim_attr};
    my @dim_tables = uniq( map { ( split( /\./, $_ ) )[0] } @dim_attr );

    # don't aggregate the full granularity
    return $base_query if scalar @dim_attr == scalar @{ $self->{dimension} };

    my $aggregate = $self->aggregate(@dim_tables);

    # only necessary if the aggregate
    # does not exist
    $aggregate->create();

    my $fact_table = $self->{name};
    my $aggr_table = $aggregate->name();

    if ($aggr_table) {
        $base_query =~ s/$fact_table/$aggr_table/gs;
    }

    return $base_query;
}

sub prepare {
    my $self = shift;

    $self->{sth} = $self->{dbh}->prepare(@_);

    return $self->{sth};
}

sub _join_str {
    my ( $self, $dim_table ) = @_;
    my $fact_table = $self->{name};
    return "    $dim_table ON $fact_table.$dim_table = $dim_table.id";
}

1;

__END__

=head1 NAME

DW::Fact - The great new DW::Fact!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use DW::Dimension;

    my $foo = DW::Dimension->new();
 

=head1 AUTHOR

Nelson Ferraz, C<< <nferraz at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-dw at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=DW>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc DW::Fact

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=DW>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/DW>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/DW>

=item * Search CPAN

L<http://search.cpan.org/dist/DW/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 Nelson Ferraz.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.
