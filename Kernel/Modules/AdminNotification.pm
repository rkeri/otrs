# --
# Kernel/Modules/AdminNotification.pm - provides admin notification translations
# Copyright (C) 2001-2010 OTRS AG, http://otrs.org/
# --
# $Id: AdminNotification.pm,v 1.33 2010/11/23 00:10:35 en Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AdminNotification;

use strict;
use warnings;

use Kernel::System::Notification;
use Kernel::System::HTMLUtils;

use vars qw($VERSION);
$VERSION = qw($Revision: 1.33 $) [1];

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # check all needed objects
    for my $Needed (qw(ParamObject DBObject LayoutObject ConfigObject LogObject)) {
        if ( !$Self->{$Needed} ) {
            $Self->{LayoutObject}->FatalError( Message => "Got no $Needed!" );
        }
    }

    $Self->{NotificationObject} = Kernel::System::Notification->new(%Param);
    $Self->{HTMLUtilsObject}    = Kernel::System::HTMLUtils->new(%Param);

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my @Params = (qw(Name Type Charset Language Subject Body UserID));
    my %GetParam;
    my $Note = '';
    for my $Parameter (@Params) {
        $GetParam{$Parameter} = $Self->{ParamObject}->GetParam( Param => $Parameter ) || '';
    }
    if ( !$GetParam{Language} && $GetParam{Name} ) {
        if ( $GetParam{Name} =~ /^(.+?)(::.*)/ ) {
            $GetParam{Language} = $1;
        }
    }

    # get content type
    my $ContentType = 'text/plain';
    if ( $Self->{LayoutObject}->{BrowserRichText} ) {
        $ContentType = 'text/html';
    }

    # ------------------------------------------------------------ #
    # get data 2 form
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Change' ) {
        my %Notification = $Self->{NotificationObject}->NotificationGet(%GetParam);
        my $Output       = $Self->{LayoutObject}->Header();
        $Output .= $Self->{LayoutObject}->NavigationBar();
        $Output .= $Self->_MaskNotificationForm(
            %GetParam,
            %Param,
            %Notification,
        );
        $Output .= $Self->{LayoutObject}->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # update action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'ChangeAction' ) {
        my %Errors;
        my $Update;

        # check for needed data
        for my $Needed (qw(Subject Body)) {
            if ( !$GetParam{$Needed} ) {
                $Errors{ $Needed . 'Invalid' } = 'ServerError';
            }
        }

        if ( !%Errors ) {

            # challenge token check for write action
            $Self->{LayoutObject}->ChallengeTokenCheck();

            $Update = $Self->{NotificationObject}->NotificationUpdate(
                %GetParam,
                ContentType => $ContentType,
                UserID      => $Self->{UserID},
            );
            if ($Update) {
                $Note = $Self->{LayoutObject}->Notify( Info => 'Notification updated!' );
            }
        }

        if ( %Errors || !$Update ) {
            my %Notification = $Self->{NotificationObject}->NotificationGet(%GetParam);
            my $Output       = $Self->{LayoutObject}->Header();
            $Output .= $Self->{LayoutObject}->NavigationBar();
            $Output .= $Self->_MaskNotificationForm(
                %GetParam,
                %Param,
                %Notification,
                %Errors,
            );
            $Output .= $Self->{LayoutObject}->Footer();
            return $Output;
        }
    }

    # ------------------------------------------------------------ #
    # else ! print form
    # ------------------------------------------------------------ #
    my $Output = $Self->{LayoutObject}->Header();
    $Output .= $Self->{LayoutObject}->NavigationBar();
    $Output .= $Note;
    $Self->{Action}    = 'AdminNotification';
    $Self->{Subaction} = '';
    $Output .= $Self->_MaskNotificationForm();
    $Output .= $Self->{LayoutObject}->Footer();
    return $Output;
}

sub _MaskNotificationForm {
    my ( $Self, %Param ) = @_;

    # build NotificationOption string
    $Param{NotificationOption} = $Self->{LayoutObject}->BuildSelection(
        Data       => { $Self->{NotificationObject}->NotificationList() },
        Name       => 'Name',
        Size       => 15,
        SelectedID => $Param{Name},
        HTMLQuote  => 1,
    );

    #Show update form
    if ( $Self->{Subaction} ) {
        $Self->{LayoutObject}->Block(
            Name => 'ActionList',
        );
        $Self->{LayoutObject}->Block(
            Name => 'ActionOverview',
        );
        $Self->{LayoutObject}->Block(
            Name => 'OverviewUpdate',
            Data => \%Param,
        );
    }
    else {

        $Self->{LayoutObject}->Block(
            Name => 'LanguageFilter',
        );
        $Self->{LayoutObject}->Block(
            Name => 'NotificationFilter',
        );
        $Self->{LayoutObject}->Block(
            Name => 'OverviewResult',
        );

        # Get notifications types.

        my @Types;
        my $SQL
            = "SELECT DISTINCT notification_type FROM "
            . "notifications ORDER BY notification_type ASC";

        $Self->{DBObject}->Prepare( SQL => $SQL );
        while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
            push( @Types, $Row[0] );
        }

        # get lenguages
        my %Languages = %{ $Self->{ConfigObject}->{DefaultUsedLanguages} };

        for my $Language ( sort { lc($a) cmp lc($b) } keys %Languages ) {
            for my $NotificationType (@Types) {
                $Self->{LayoutObject}->Block(
                    Name => 'OverviewResultRow',
                    Data => {
                        Language => $Languages{$Language},
                        Type     => $NotificationType,
                        Name     => $Language . '::' . $NotificationType,
                    },
                );
            }
        }
    }

    # add rich text editor
    if ( $Self->{LayoutObject}->{BrowserRichText} ) {
        $Self->{LayoutObject}->Block(
            Name => 'RichText',
            Data => \%Param,
        );

        # reformat from plain to html
        if ( $Param{ContentType} && $Param{ContentType} =~ /text\/plain/i ) {
            $Param{Body} = $Self->{HTMLUtilsObject}->ToHTML(
                String => $Param{Body},
            );
        }
    }
    else {

        # reformat from html to plain
        if ( $Param{ContentType} && $Param{ContentType} =~ /text\/html/i ) {
            $Param{Body} = $Self->{HTMLUtilsObject}->ToAscii(
                String => $Param{Body},
            );
        }
    }

    return $Self->{LayoutObject}->Output(
        TemplateFile => 'AdminNotification',
        Data         => \%Param
    );
}

1;