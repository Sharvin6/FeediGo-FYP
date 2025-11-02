import 'package:feedigo_app/BeneficiaryScreens/beneficiary_confirm_pickup_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_create_pickup_details_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_dashboard_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_donation_details_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_edit_pickup_details_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_match_results_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_pickup_schedule_details_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_pickup_schedule_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_request_food_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_request_history_screen.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/donation_details_screen.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/donor_view_schedule.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/history_screen_donor.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/requester_details_screen.dart';
import 'package:feedigo_app/FoodBankScreens/confirm_pickup_screen.dart';
import 'package:feedigo_app/FoodBankScreens/edit_pickup_details_screen.dart';
import 'package:feedigo_app/FoodBankScreens/match_results_screen.dart';
import 'package:feedigo_app/FoodBankScreens/pickup_schedule_details_screen.dart';
//import 'package:feedigo_app/FoodBankScreens/available_donations_screen.dart';
import 'package:feedigo_app/FoodBankScreens/create_pickup_details_screen.dart';
import 'package:feedigo_app/FoodBankScreens/food_bank_dashboard_screen.dart';
import 'package:feedigo_app/FoodBankScreens/foodbank_donation_details_screen.dart';
import 'package:feedigo_app/FoodBankScreens/pickup_schedule_screen.dart';
import 'package:feedigo_app/FoodBankScreens/request_food_screen.dart';
import 'package:feedigo_app/FoodBankScreens/request_history_screen.dart';
import 'package:feedigo_app/Settings/edit_profile_screen.dart';
import 'package:feedigo_app/Settings/change_password_screen.dart';
import 'package:feedigo_app/Settings/settings_screen.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/edit_donation_screen.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/post_donation_screen.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/donor_dashboard_screen.dart';
import 'package:feedigo_app/FirstScreen/OnboardingScreen.dart';
import 'package:feedigo_app/RoleSelectAndCreateProfile/profile_setup_screen.dart';
import 'package:feedigo_app/RoleSelectAndCreateProfile/profile_success_screen.dart';
import 'package:feedigo_app/RoleSelectAndCreateProfile/role_selection_screen.dart';
import 'package:feedigo_app/SignInScreen/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(FeediGoApp());
}

class FeediGoApp extends StatelessWidget {
  const FeediGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FeediGo',
      theme: ThemeData(primarySwatch: Colors.deepOrange),
      initialRoute: '/',
      routes: {
        //first screen
        '/': (_) => OnboardingScreen(),
        //login and register
        '/auth': (_) => const AuthScreen(),
        '/role_selection': (_) => const RoleSelectionScreen(),
        //profile setup
        '/profile_setup': (_) => const ProfileSetupScreen(),
        //'/profile_success': (_) => const ProfileSuccessScreen(),
        //donor screens
        '/donor_dashboard': (_) => const DonorDashboardScreen(),
        '/post_donation': (_) => const PostDonationScreen(),
        '/donation_details': (_) => const DonationDetailsScreen(),
        '/edit_donation': (ctx) {
          final id = ModalRoute.of(ctx)!.settings.arguments as String?;
          return EditDonationScreen(donationId: id);
        },
        '/donor_view_schedule': (_) => const DonorViewScheduleScreen(),

        '/donation_history': (_) => const DonationHistoryScreen(),
        '/requestor_details': (_) => const RequesterDetailsScreen(),
        //settings
        '/settings_screen': (_) => const SettingsScreen(),
        '/edit_profile': (_) => const EditProfileScreen(),
        '/change_password': (_) => const ChangePasswordScreen(),
        //food bank screens
        '/foodbank_dashboard': (_) => const FoodBankDashboardScreen(),
        //'/available_donations': (_) => const AvailableDonationsScreen(),
        '/fb_donation_details': (_) => const FoodBankDonationDetailsScreen(),
        '/request_history': (_) => const RequestHistoryScreen(),
        '/pickup_schedule': (_) => const PickupScheduleScreen(),
        '/create_pickup_details': (_) => const CreatePickupDetailsScreen(),
        '/pickup_schedule_details': (_) => const PickupScheduleDetailsScreen(),
        '/edit_pickup_details': (context) => const EditPickupDetailsScreen(),
        '/confirm_pickup': (_) => const ConfirmPickupScreen(),
        '/request_food': (_) => const RequestFoodScreen(),
        '/match_results': (_) => const MatchResultsScreen(),
        //beneficiary_screens
        '/beneficiary_dashboard': (_) => const BeneficiaryDashboardScreen(),
        '/beneficiary_request_food':
            (_) => const BeneficiaryRequestFoodScreen(),
        '/beneficiary_match_results':
            (_) => const BeneficiaryMatchResultsScreen(),
        '/beneficiary_request_history':
            (_) => const BeneficiaryRequestHistoryScreen(),
        '/beneficiary_donation_details':
            (_) => const BeneficiaryDonationDetailsScreen(),
        '/beneficiary_pickup_schedule':
            (_) => const BeneficiaryPickupScheduleScreen(),
        '/beneficiary_create_pickup':
            (_) => const BeneficiaryCreatePickupDetailsScreen(),
        '/beneficiary_pickup_schedule_details':
            (_) => const BeneficiaryPickupScheduleDetailsScreen(),
        '/beneficiary_edit_pickup_details':
            (context) => const BeneficiaryEditPickupDetailsScreen(),
        '/beneficiary_confirm_pickup':
            (_) => const BeneficiaryConfirmPickupScreen(),
      },
    );
  }
}
