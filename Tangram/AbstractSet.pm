# (c) Sound Object Logic 2000-2001

use strict;

use Tangram::Coll;

package Tangram::AbstractSet;

use base qw( Tangram::Coll );

use Carp;

sub save
{
	my ($self, $cols, $vals, $obj, $members, $storage, $table, $id) = @_;

	foreach my $coll (keys %$members)
	{
		next if tied $obj->{$coll};
		next unless defined $obj->{$coll};

		my $class = $members->{$coll}{class};

		foreach my $item ($obj->{$coll}->members)
		{
			Tangram::Coll::bad_type($obj, $coll, $class, $item)
					if $^W && !$item->isa($class);
			if ($members->{$coll}->{deep_update}) {
				$storage->_save($item);
			} else {
				$storage->insert($item)	unless $storage->id($item);
		        }
		}
	}

	$storage->defer(sub { $self->defered_save(shift, $obj, $members, $id) } );

	return ();
}

sub get_exporter
  {
	my ($self, $context) = @_;
	my $field = $self->{name};
	
	return $self->{deep_update} ?
	  sub {
		my ($obj, $context) = @_;
		
		# has collection been loaded? if not, then it hasn't been modified
		return if tied $obj->{$field};
		
		my $storage = $context->{storage};
		
		foreach my $item ($obj->{$field}->members) {
		  $storage->_save($item);
		}
		
		$storage->defer(sub { $self->defered_save(shift, $obj, $field, $self) } );
		
		return ();
	  }
	: sub {
	  my ($obj, $context) = @_;
	  
	  # has collection been loaded? if not, then it hasn't been modified
	  return if tied $obj->{$field};
	  
	  my $storage = $context->{storage};
	  
	  foreach my $item ($obj->{$field}->members) {
		$storage->insert($item)
		  unless $storage->id($item);
	  }
	  
	  $storage->defer(sub { $self->defered_save(shift, $obj, $field, $self) } );
	  
	  return ();
	}
  }

sub update
{
	my ($self, $storage, $obj, $member, $insert, $remove) = @_;

	return unless defined $obj->{$member};

	my $coll_id = $storage->id($obj);
	my $old_states = $storage->{scratch}{ref($self)}{$coll_id};
	my $old_state = $old_states->{$member};
	my %new_state = ();

	foreach my $item ($obj->{$member}->members)
	{
		my $item_id = $storage->id($item) || croak "member $item has no id";
      
		unless (exists $old_state->{$item_id})
		{
			$insert->($storage->{export_id}->($item_id));
		}

		$new_state{$item_id} = 1;
	}

	foreach my $del (keys %$old_state)
	{
		next if $new_state{$del};
		$remove->($storage->{export_id}->($del));
	}

	$old_states->{$member} = \%new_state;
	$storage->tx_on_rollback( sub { $old_states->{$member} = $old_state } );
}

sub remember_state
{
	my ($self, $def, $storage, $obj, $member, $set) = @_;

	my %new_state;
	@new_state{ map { $storage->id($_) } $set->members } = 1 x $set->size;
	$storage->{scratch}{ref($self)}{$storage->id($obj)}{$member} = \%new_state;
}

sub content
{
	shift;
	shift->members;
}

1;
