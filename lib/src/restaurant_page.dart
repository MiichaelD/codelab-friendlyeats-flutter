// Copyright 2020 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sliver_fab/sliver_fab.dart';

import 'model/data.dart' as data;
import 'model/restaurant.dart';
import 'model/review.dart';
import 'widgets/app_bar.dart';
import 'widgets/dialogs/review_create.dart';
import 'widgets/empty_list.dart';
import 'widgets/review.dart';

class RestaurantPage extends StatefulWidget {
  static const route = '/restaurant';

  final String _restaurantId;

  RestaurantPage({Key key, @required String restaurantId})
      : _restaurantId = restaurantId,
        super(key: key);

  @override
  _RestaurantPageState createState() =>
      _RestaurantPageState(restaurantId: _restaurantId);
}

class _RestaurantPageState extends State<RestaurantPage> {
  final String restaurantId;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  FirebaseUser _firebaseUser;

  _RestaurantPageState({@required this.restaurantId}) {
    data.getRestaurant(restaurantId).then((Restaurant restaurant) {
      _currentReviewSubscription?.cancel();
      _restaurant = restaurant;
      // Initialize the reviews snapshot...
      _currentReviewSubscription = _restaurant.reference
          .collection('ratings')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen((QuerySnapshot reviewSnap) {
        setState(() {
          _isLoading = false;
          _reviews = reviewSnap.documents.map((DocumentSnapshot doc) {
            return Review.fromSnapshot(doc);
          }).toList();
        });
      });
    });

    FirebaseAuth.instance.currentUser().then((firebaseUser) async {
      this._firebaseUser = firebaseUser;
      if (firebaseUser == null) {
        debugPrint('Signing anonymously.');
        FirebaseAuth.instance
            .signInAnonymously()
            .then(_onAuthResult)
            .catchError((error) =>
                debugPrint('Error while anonymously signing in: $error'));
      } else {
        _firebaseUser.reload();
      }
    });
  }

  void _onAuthResult(AuthResult auth,
      [AuthCredential credential, bool showReviewDialog]) async {
    debugPrint('''
      OnAuthResult: currentUser: ${_firebaseUser.displayName}\
      (${_firebaseUser.uid})${_firebaseUser.isAnonymous ? '[anon]' : ''}''');
    await auth.user.reload();
    _firebaseUser = auth.user;
    debugPrint('''
      newUser: ${auth.user.displayName}(${auth.user.uid})\
      [${auth.user.isAnonymous ? 'anon' : auth.user.email}]''');
    if (showReviewDialog) {
      showAddReviewDialog();
    }
  }

  @override
  void dispose() {
    _currentReviewSubscription?.cancel();
    super.dispose();
  }

  bool _isLoading = true;
  StreamSubscription<QuerySnapshot> _currentReviewSubscription;

  Restaurant _restaurant;
  List<Review> _reviews = <Review>[];

  void _onCreateReviewPressed(BuildContext context) async {
    debugPrint('''
        User signed: 
        ${_firebaseUser.displayName}(${_firebaseUser.uid})
        ${_firebaseUser.isAnonymous ? '[anon]' : '${_firebaseUser.email}'}''');

    var isSignedIn = await _googleSignIn.isSignedIn();
    if (isSignedIn || _googleSignIn.currentUser != null) {
      debugPrint('''
        User already signed in using Google credentials.: 
        ${_googleSignIn.currentUser?.displayName}\
        (${_googleSignIn.currentUser?.id})\
        ${_googleSignIn.currentUser?.email}''');
      showAddReviewDialog(); // As signed in user
      return;
    }
    _googleSignIn.signIn().then((googleSignInAccount) async {
      if (googleSignInAccount == null) {
        debugPrint('User cancelled Google login');
        showAddReviewDialog(); // As signed in user
      } else {
        final googleSignInAuthentication =
            await googleSignInAccount.authentication;
        final credential = GoogleAuthProvider.getCredential(
            accessToken: googleSignInAuthentication.accessToken,
            idToken: googleSignInAuthentication.idToken);
        // Note: Linking doesn't update current user's name.
//        _firebaseUser
//            .linkWithCredential(credential)
//            .then((authResult) => _onAuthResult(authResult, credential, true))
//            .catchError((error) {
//          debugPrint('Error while linking Google credentials $error');

        FirebaseAuth.instance
            .signInWithCredential(credential)
            .then((authResult) => _onAuthResult(authResult, credential, true))
            .catchError((error) {
          debugPrint('Error while singing in with Google credentials $error');
          showAddReviewDialog(); // As anonymous user
        });
//        });
      }
    }).catchError((error) {
      debugPrint('Error while singing in with Google credentials2 $error');
      showAddReviewDialog(); // As anonymous user
    });
  }

  void showAddReviewDialog() async {
    final newReview = await showDialog<Review>(
      context: context,
      builder: (_) => ReviewCreateDialog(
        user: _firebaseUser,
      ),
    );
    if (newReview != null) {
      // Save the review
      return data.addReview(
        restaurantId: _restaurant.id,
        review: newReview,
      );
    }
  }

  void _onAddRandomReviewsPressed() async {
    // Await adding a random number of random reviews
    final numReviews = Random().nextInt(5) + 5;
    for (var i = 0; i < numReviews; i++) {
      await data.addReview(
        restaurantId: _restaurant.id,
        review: Review.random(
          userId: _firebaseUser?.uid,
          userName: _firebaseUser?.displayName == null
              ? 'Anonymous (${kIsWeb ? "Web" : "Mobile"})'
              : _firebaseUser.displayName,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? Center(child: CircularProgressIndicator())
        : Scaffold(
            body: Builder(
              builder: (context) => SliverFab(
                floatingWidget: FloatingActionButton(
                  tooltip: 'Add a review',
                  backgroundColor: Colors.amber,
                  child: Icon(Icons.add),
                  onPressed: () => _onCreateReviewPressed(context),
                ),
                floatingPosition: FloatingPosition(right: 16),
                expandedHeight: RestaurantAppBar.appBarHeight,
                slivers: <Widget>[
                  RestaurantAppBar(
                    restaurant: _restaurant,
                    onClosePressed: () => Navigator.pop(context),
                  ),
                  _reviews.isNotEmpty
                      ? SliverPadding(
                          padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate(_reviews
                                .map((Review review) =>
                                    RestaurantReview(review: review))
                                .toList()),
                          ),
                        )
                      : SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyListView(
                            child: Text('${_restaurant.name} has no reviews.'),
                            onPressed: _onAddRandomReviewsPressed,
                          ),
                        ),
                ],
              ),
            ),
          );
  }
}

class RestaurantPageArguments {
  final String id;

  RestaurantPageArguments({@required this.id});
}
