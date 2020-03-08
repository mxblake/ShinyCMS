package ShinyCMS::Controller::Newsletters;

use Moose;
use namespace::autoclean;

BEGIN { extends 'ShinyCMS::Controller'; }


=head1 NAME

ShinyCMS::Controller::Newsletters

=head1 DESCRIPTION

Controller for ShinyCMS newsletter features.

=cut


=head1 METHODS

=head2 base

Set up path and stash some useful stuff.

=cut

sub base : Chained( '/base' ) : PathPart( 'newsletters' ) : CaptureArgs( 0 ) {
	my ( $self, $c ) = @_;

	# Stash the controller name
	$c->stash->{ controller } = 'Newsletters';
}


=head2 index

Display a list of recent newsletters.

=cut

sub index : Chained( 'base' ) : PathPart( '' ) : Args( 0 ) {
	my ( $self, $c ) = @_;

	$c->go( 'view_newsletters' );
}


=head2 view_newsletter

View a newsletter.

=cut

sub view_newsletter : Chained( 'get_newsletter' ) : PathPart( '' ) : Args( 0 ) {
	my ( $self, $c ) = @_;

	# Set the TT template to use
	$c->stash->{ template } 
		= 'newsletters/newsletter-templates/'. $c->stash->{ newsletter }->template->filename;
}


=head2 view_newsletters

Display a page of newsletters.

=cut

sub view_newsletters : Chained( 'base' ) : PathPart( 'view' ) : Args( 0 ) {
	my ( $self, $c ) = @_;

	my $page  = $c->request->param( 'page'  ) ? $c->request->param( 'page'  ) : 1;
	my $count = $c->request->param( 'count' ) ? $c->request->param( 'count' ) : 10;

	my $newsletters = $c->model( 'DB::Newsletter' )->search(
		{
			sent     => { '<=' => \'current_timestamp' },
		},
		{
			order_by => { -desc => 'sent' },
			page     => $page,
			rows     => $count,
		},
	);

	$c->stash->{ page_num    } = $page;
	$c->stash->{ post_count  } = $count;
	$c->stash->{ newsletters } = $newsletters;
}


=head2 get_newsletter
Get the details for a newsletter.


=cut

sub get_newsletter : Chained( 'base' ) : PathPart( '' ) : CaptureArgs( 3 ) {
	my ( $self, $c, $year, $month, $url_title ) = @_;

	my $month_start = DateTime->new(
		day   => 1,
		month => $month,
		year  => $year,
	);
	my $month_end = $month_start->clone->add( months => 1 );

	# Get the newsletter
	$c->stash->{ newsletter } = $c->model( 'DB::Newsletter' )->search({
		url_title => $url_title,
		-and => [
				sent => { '<=' => \'current_timestamp' },
				sent => { '>=' => $month_start->ymd    },
				sent => { '<=' => $month_end->ymd      },
			],
	})->first;

	unless ( $c->stash->{ newsletter } ) {
		$c->flash->{ error_msg } = 'Specified newsletter not found.';
		$c->response->redirect( $c->uri_for( '/newsletters' ) );
		$c->detach;
	}

	# Get newsletter elements
	my @elements = $c->model( 'DB::NewsletterElement' )->search({
		newsletter => $c->stash->{ newsletter }->id,
	});
	$c->stash->{ newsletter_elements } = \@elements;

	# Stash site details
	$c->stash->{ site_name } = $c->config->{ site_name };
	$c->stash->{ site_url  } = $c->uri_for( '/' );

	# Build up 'elements' structure for use by templates
	foreach my $element ( @elements ) {
		$c->stash->{ elements }->{ $element->name } = $element->content;
	}
}


# ========== ( Mailing Lists ) ==========

=head2 lists

View a list of all mailing lists this user is subscribed to.

=cut

sub lists : Chained( 'base' ) : PathPart( 'lists' ) : Args() {
	my ( $self, $c, $token ) = @_;

	my $mail_recipient;
	my $email;
	if ( $token ) {
		# Get email address that matches URL token
		$mail_recipient = $c->model('DB::MailRecipient')->search({
			token => $token,
		})->first;
		if ( $mail_recipient ) {
			# Dig out the email address
			$email = $mail_recipient->email;
			# Put the token in the stash for inclusion in form
			$c->stash->{ token } = $token;
		}
		else {
			$c->stash->{ error_msg } = 'Subscriber not found.';
			$c->detach;
		}
	}
	elsif ( $c->user_exists ) {
		# Use the logged-in user's email address
		$email = $c->user->email;
		$mail_recipient = $c->model( 'DB::MailRecipient' )->search({
			email => $email,
		})->first;
		$c->stash->{ token } = $mail_recipient->token if $mail_recipient;
	}

	# Fetch the list of mailing lists for this user
	if ( $email and $mail_recipient ) {
		my $lists = $mail_recipient->subscribed_to_lists;
		my @user_lists = $lists->all;
		my @subbed_list_ids = $lists->get_column('id')->all;
		$c->stash->{ user_lists } = \@user_lists;
		my %hashsubs = map { $_ => 1 } @subbed_list_ids;
		$c->stash->{ user_is_subscribed_to_list } = \%hashsubs;

		# Fetch details of private mailing lists that this user is subscribed to
		my $private_lists = $c->model( 'DB::MailingList' )->search(
			{
				user_can_sub   => 0,
				user_can_unsub => 1,
				id => { -in => \@subbed_list_ids },
			},
			{
				order_by => 'id',
			}
		);
		$c->stash->{ private_lists } = $private_lists if $private_lists->count > 0;

		# Fetch details of queued emails this user is due to receive
		my $queued_emails = $c->model( 'DB::QueuedEmail' )->search({
			recipient => $mail_recipient->id,
		});
		# De-duplicate the list of autoresponders associated with those emails
		my %autoresponders;
		while ( my $queued_email = $queued_emails->next ) {
			$autoresponders{ $queued_email->email->autoresponder->id } = 1;
		}
		my @autoresponder_ids = keys %autoresponders;
		# Fetch the autoresponder details
		my $autoresponders = $c->model( 'DB::Autoresponder' )->search({
			id => { -in => \@autoresponder_ids },
		});
		# And stash them
		$c->stash->{ autoresponders } = $autoresponders if $autoresponders->count > 0;
	}
	else {
		# If no email address, treat as new subscriber; no existing subscriptions,
		# and need to get email address (and, optionally, name) from them as well.

		# TODO: think about this^ some more - currently it allows DOS attacks,
		# and possibly leaks private data.  For now, bail out here.
		$c->stash->{ status_msg } = 'No subscriptions found.';
		$c->detach;
	}

	# Fetch the details of all public mailing lists
	my $public_lists = $c->model( 'DB::MailingList' )->search(
		{
			user_can_sub => 1,
		},
		{
			order_by => 'id',
		}
	);
	$c->stash->{ public_lists } = $public_lists if $public_lists->count > 0;
}


=head2 lists_update

Update which mailing lists this user is subscribed to.

=cut

sub lists_update : Chained( 'base' ) : PathPart( 'lists/update' ) : Args( 0 ) {
	my ( $self, $c ) = @_;

	# Get the email token from the form, if included
	my $token = $c->request->param('token') || undef;

	my $email;
	my $mail_recipient;
	if ( $token ) {
		# Get email address that matches URL token
		$mail_recipient = $c->model('DB::MailRecipient')->find({
			token => $token,
		});
		if ( $mail_recipient ) {
			# Dig out the email address
			$email = $mail_recipient->email;
		}
	}
	else {
		# Get the email address from the form, if given
# TODO: figure out what we're doing about non-logged-in users with no token
#		$email = $c->request->param('email') || undef;
	}
	# Use the logged-in user's email address if one hasn't been specified
	if ( $c->user_exists and not $email ) {
		$email = $c->user->email;
		$mail_recipient = $c->model('DB::MailRecipient')->find({
			email => $email,
		});
	}

	# Bail out if we still don't have an email address
	unless ( $email ) {
		$c->flash->{ error_msg } = 'No email address specified.';
		my $uri = $c->uri_for( '/newsletters/lists' );
		$c->response->redirect( $uri );
		$c->detach;
	}

	# Create a new mail recipient record if one doesn't already exist
	unless ( $mail_recipient ) {
		my $now = DateTime->now;
		my $token = $self->generate_email_token( $c, $email );
		# Create new mail recipient
		$mail_recipient = $c->model('DB::MailRecipient')->create({
			email => $email,
			token => $token,
			name  => $c->request->param('name') || undef,
		});
	}

	# Get the sub/unsub details from form
	my @new_subs = $c->request->param( 'lists' );

	# Delete existing (old) subscriptions
	$mail_recipient->subscriptions->delete;

	# Create new subscriptions
	foreach my $list_id ( @new_subs ) {
		$mail_recipient->subscriptions->create({ list => $list_id });
	}

	# Delete unwanted queued autoresponder emails
	my %params = %{ $c->request->params };
	my @keys = keys %params;
	foreach my $key ( @keys ) {
		next unless $key =~ m/^autoresponder_(\d+)/;
		my $ar_id = $1;
		unless ( $c->request->param( 'keep_autoresponder_'.$1 ) ) {
			my @emails = $c->model('DB::Autoresponder')->find({
				id => $ar_id,
			})->autoresponder_emails->all;
			my @email_ids;
			foreach my $e ( @emails ) {
				push @email_ids, $e->id,
			}
			$mail_recipient->queued_emails->search({
				email => { -in => \@email_ids },
			})->delete;
		}
	}

	# Redirect back to the 'manage your subscriptions' page
	$c->flash->{ status_msg } = 'Your subscriptions have been updated';
	my $uri;
	$uri = $c->uri_for( 'lists', $token ) if     $token;
	$uri = $c->uri_for( 'lists'         ) unless $token;
	$c->response->redirect( $uri );
}


# ========= ( Autoresponders ) ==========

=head2 autoresponder_subscribe

Subscribe an email address to an autoresponder

=cut

sub autoresponder_subscribe : Chained( 'base' ) : PathPart( 'autoresponder/subscribe' ) : Args( 0 ) {
	my ( $self, $c ) = @_;

	# Validate inputs
	my $email = $c->request->param( 'email' );
	$self->error_redirect( $c, 'No email address provided.' ) unless $email;
	my $ar_name = $c->request->param( 'autoresponder' );
	$self->error_redirect( $c, 'No autoresponder specified.' ) unless $ar_name;

	# Find specified autoresponder
	my $ar = $c->model('DB::Autoresponder')->search({
		url_name => $ar_name,
	})->first;
	$self->error_redirect( $c,  'Could not find specified autoresponder.' ) unless $ar;

	if ( $ar->has_captcha ) {
		# Check if they passed the reCaptcha test
		$self->error_redirect( $c, 'You must fill in the reCaptcha.' ) 
			unless $c->request->param( 'g-recaptcha-response' );

		my $result = $self->recaptcha_result( $c );
		$self->error_redirect( $c,
			'You did not fill in the reCaptcha correctly, please try again.'
		) unless $result->{ is_valid };
	}

	# Find or create mail recipient record for this email address
	my $recipient = $c->model('DB::MailRecipient')->find({
		email => $email,
	});
	my $name = $c->request->param('name');
	if ( $recipient ) {
		if ( $name ) {
			if ( $name ne $recipient->name ) {
				$recipient->update({ name => $name });
			}
		}
	}
	else {
		my $token = $self->generate_email_token( $c, $email );
		$recipient = $c->model('DB::MailRecipient')->create({
			name  => $name,
			email => $email,
			token => $token,
		});
	}

	# Create queued emails
	my @ar_emails = $ar->autoresponder_emails->all;
	foreach my $ar_email ( @ar_emails ) {
		my $send = DateTime->now->add( days => $ar_email->delay );
		$recipient->queued_emails->create({
			email => $ar_email->id,
			send  => $send,
		});
	}

	# Return to homepage or specified URL, display a 'success' message
	if ( $c->request->param('status_msg') ) {
		$c->flash->{ status_msg } = $c->request->param('status_msg');
	}
	else {
		$c->flash->{ status_msg } = 'Subscription successful.';
	}
	my $uri;
	if ( $c->request->param('redirect_url') ) {
		$uri = $c->request->param('redirect_url');
	}
	else {
		$uri = $c->uri_for( '/' );
	}
	$c->response->redirect( $uri );
}


# ========== ( utility methods ) ==========

=head2 error_redirect

Set an error message and redirect - used in autoresponder_subscribe()

=cut

sub error_redirect : Private {
	my ( $self, $c, $error_msg ) = @_;

	$c->flash->{ error_msg } = $error_msg;

	my $url = $c->request->referer ? $c->request->referer : $c->uri_for( '/' );

	$c->response->redirect( $url );
	$c->detach;
}


=head2 generate_email_token

Generate an email address token.

=cut

sub generate_email_token : Private {
	my ( $self, $c, $email ) = @_;

	my $now = DateTime->now->datetime;
	my $md5 = Digest::MD5->new;
	$md5->add( $email, $now );
	my $code = $md5->hexdigest;

	return $code;
}



=head1 AUTHOR

Denny de la Haye <2019@denny.me>

=head1 COPYRIGHT

Copyright (c) 2009-2019 Denny de la Haye.

=head1 LICENSING

ShinyCMS is free software; you can redistribute it and/or modify it under the
terms of either:

a) the GNU General Public License as published by the Free Software Foundation;
   either version 2, or (at your option) any later version, or

b) the "Artistic License"; either version 2, or (at your option) any later
   version.

https://www.gnu.org/licenses/gpl-2.0.en.html
https://opensource.org/licenses/Artistic-2.0

=cut

__PACKAGE__->meta->make_immutable;

1;
