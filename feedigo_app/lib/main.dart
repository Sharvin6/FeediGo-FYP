//This file initializes Firebase, launches the FeediGo app, and centrally manages navigation routes for donors, food banks, and beneficiaries.

// ===================== IMPORTS =====================
import 'package:flutter/material.dart'; // Flutter core UI package
import 'package:firebase_core/firebase_core.dart'; // Firebase core package (required to initialize Firebase)

// ----------- AUTH & ONBOARDING -----------
import 'package:feedigo_app/FirstScreen/OnboardingScreen.dart';
import 'package:feedigo_app/SignInScreen/auth_screen.dart';

// ----------- ROLE & PROFILE SETUP -----------
import 'package:feedigo_app/RoleSelectAndCreateProfile/role_selection_screen.dart';
import 'package:feedigo_app/RoleSelectAndCreateProfile/profile_setup_screen.dart';
import 'package:feedigo_app/RoleSelectAndCreateProfile/profile_success_screen.dart';

// ----------- DONOR SCREENS -----------
import 'package:feedigo_app/DonorScreens/PostDonation/donor_dashboard_screen.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/post_donation_screen.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/donation_details_screen.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/edit_donation_screen.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/donor_view_schedule.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/history_screen_donor.dart';
import 'package:feedigo_app/DonorScreens/PostDonation/requester_details_screen.dart';

// ----------- FOOD BANK SCREENS -----------
import 'package:feedigo_app/FoodBankScreens/food_bank_dashboard_screen.dart';
import 'package:feedigo_app/FoodBankScreens/foodbank_donation_details_screen.dart';
import 'package:feedigo_app/FoodBankScreens/request_history_screen.dart';
import 'package:feedigo_app/FoodBankScreens/pickup_schedule_screen.dart';
import 'package:feedigo_app/FoodBankScreens/create_pickup_details_screen.dart';
import 'package:feedigo_app/FoodBankScreens/pickup_schedule_details_screen.dart';
import 'package:feedigo_app/FoodBankScreens/edit_pickup_details_screen.dart';
import 'package:feedigo_app/FoodBankScreens/confirm_pickup_screen.dart';
import 'package:feedigo_app/FoodBankScreens/request_food_screen.dart';
import 'package:feedigo_app/FoodBankScreens/match_results_screen.dart';

// ----------- BENEFICIARY SCREENS -----------
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_dashboard_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_request_food_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_match_results_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_request_history_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_donation_details_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_pickup_schedule_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_create_pickup_details_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_pickup_schedule_details_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_edit_pickup_details_screen.dart';
import 'package:feedigo_app/BeneficiaryScreens/beneficiary_confirm_pickup_screen.dart';

// ----------- SETTINGS -----------
import 'package:feedigo_app/Settings/settings_screen.dart';
import 'package:feedigo_app/Settings/edit_profile_screen.dart';
import 'package:feedigo_app/Settings/change_password_screen.dart';

// ===================== MAIN FUNCTION =====================

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensures Flutter engine is fully initialized before using async code
  await Firebase.initializeApp(); // Initialize Firebase before running the app
  runApp(const FeediGoApp()); // Run the main application widget
}

// ===================== ROOT APP WIDGET =====================

class FeediGoApp extends StatelessWidget {
  const FeediGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Removes the debug banner
      title: 'FeediGo',
      // Global theme configuration
      theme: ThemeData(
        primarySwatch: Colors.deepOrange, // Hunger-relief themed color
      ),

      initialRoute: '/', // First screen shown when app launches
      // Centralized route management
      routes: {
        // ----------- ONBOARDING & AUTH -----------
        '/': (_) => OnboardingScreen(),
        '/auth': (_) => const AuthScreen(),

        // ----------- ROLE & PROFILE SETUP -----------
        '/role_selection': (_) => const RoleSelectionScreen(),
        '/profile_setup': (_) => const ProfileSetupScreen(),
        '/profile_success': (_) => const ProfileSuccessScreen(),

        // ----------- DONOR ROUTES -----------
        '/donor_dashboard': (_) => const DonorDashboardScreen(),
        '/post_donation': (_) => const PostDonationScreen(),
        '/donation_details': (_) => const DonationDetailsScreen(),

        // Passing donation ID using route arguments
        '/edit_donation': (context) {
          final donationId =
              ModalRoute.of(context)!.settings.arguments as String?;
          return EditDonationScreen(donationId: donationId);
        },

        '/donor_view_schedule': (_) => const DonorViewScheduleScreen(),
        '/donation_history': (_) => const DonationHistoryScreen(),
        '/requestor_details': (_) => const RequesterDetailsScreen(),

        // ----------- SETTINGS -----------
        '/settings_screen': (_) => const SettingsScreen(),
        '/edit_profile': (_) => const EditProfileScreen(),
        '/change_password': (_) => const ChangePasswordScreen(),

        // ----------- FOOD BANK ROUTES -----------
        '/foodbank_dashboard': (_) => const FoodBankDashboardScreen(),
        '/fb_donation_details': (_) => const FoodBankDonationDetailsScreen(),
        '/request_history': (_) => const RequestHistoryScreen(),
        '/pickup_schedule': (_) => const PickupScheduleScreen(),
        '/create_pickup_details': (_) => const CreatePickupDetailsScreen(),
        '/pickup_schedule_details': (_) => const PickupScheduleDetailsScreen(),
        '/edit_pickup_details': (_) => const EditPickupDetailsScreen(),
        '/confirm_pickup': (_) => const ConfirmPickupScreen(),
        '/request_food': (_) => const RequestFoodScreen(),
        '/match_results': (_) => const MatchResultsScreen(),

        // ----------- BENEFICIARY ROUTES -----------
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
        '/beneficiary_create_pickup_details':
            (_) => const BeneficiaryCreatePickupDetailsScreen(),
        '/beneficiary_pickup_schedule_details':
            (_) => const BeneficiaryPickupScheduleDetailsScreen(),
        '/beneficiary_edit_pickup_details':
            (_) => const BeneficiaryEditPickupDetailsScreen(),
        '/beneficiary_confirm_pickup':
            (_) => const BeneficiaryConfirmPickupScreen(),
      },
    );
  }
}
