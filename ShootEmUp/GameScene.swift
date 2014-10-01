//
// GameScene.swift
// SpriteKitTutorial1
//
// Written by Joey deVilla - August 2014
// Last updated September 30, 2014
// using XCode 6.0.1
//
// A simple shoot-em-up game that shows some Sprite Kit basics in Swift.
// Some of the code was adapted from the simple game featured in
// Ray Wenderlich's article, "Sprite Kit Tutorial for Beginners"
// at RayWenderlich.com
// (http://www.raywenderlich.com/42699/spritekit-tutorial-for-beginners).

import SpriteKit
import AVFoundation


// MARK: - Vector math operators and CGPoint extensions
// ====================================================
// In this app, we're using CGPoints to do some vector math (yes, there's a CGVector type,
// but in this case, it's just more convenient to use CGPoints to represent both vectors
// and points).
//
// I've marked these as private to limit the scope of these overloads and extensions
// to this file.

// Vector addition
private func + (left: CGPoint, right: CGPoint) -> CGPoint {
  return CGPoint(x: left.x + right.x, y: left.y + right.y)
}

// Vector subtraction
private func -(left: CGPoint, right: CGPoint) -> CGPoint {
  return CGPoint(x: left.x - right.x, y: left.y - right.y)
}

// Vector * scalar
private func *(point: CGPoint, factor: CGFloat) -> CGPoint {
  return CGPoint(x: point.x * factor, y:point.y * factor)
}

private extension CGPoint {
  // Get the length (a.k.a. magnitude) of the vector
  var length: CGFloat { return sqrt(self.x * self.x + self.y * self.y) }
  
  // Normalize the vector (preserve its direction, but change its magnitude to 1)
  var normalized: CGPoint { return CGPoint(x: self.x / self.length, y: self.y / self.length) }
}

// MARK: -

class GameScene: SKScene, SKPhysicsContactDelegate {
  
  // MARK: Properties
  // ================
  
  // Background music
  // ----------------
  private var backgroundMusicPlayer: AVAudioPlayer!
  
  // Game time trackers
  // ------------------
  private var lastUpdateTime: CFTimeInterval = 0  // Time when update() was last called
  private var timeSinceLastAlienSpawned: CFTimeInterval  = 0  // Seconds since the last alien was spawned
  
  // Ship sprite
  // -----------
  // For simplicity's sake, we'll use the spaceship that's provided in Images.xcassets
  // when you start a new Game project
  private let ship = SKSpriteNode(imageNamed: "Spaceship")
  
  // Physics body category bitmasks
  // ------------------------------
  // We'll use these to determine missle-alien collisions
  private let missileCategory: UInt32 = 0x1 << 0   // 00000000000000000000000000000001 in binary
  private let alienCategory: UInt32   = 0x1 << 1   // 00000000000000000000000000000010 in binary
  
  
  // MARK: Events
  // ============
  
  // Called immediately after the view presents this scene.
  override func didMoveToView(view: SKView) {
    // Start the background music player
    var error: NSError?
    let backgroundMusicURL = NSBundle.mainBundle().URLForResource("background-music", withExtension: "aiff")
    backgroundMusicPlayer = AVAudioPlayer(contentsOfURL: backgroundMusicURL, error: &error)
    backgroundMusicPlayer.numberOfLoops = -1
    backgroundMusicPlayer.prepareToPlay()
    backgroundMusicPlayer.play()
    
    // Set the game's background color to white
    backgroundColor = SKColor(red: 1, green: 1, blue: 1, alpha: 1)
    
    // Position the player's ship halfway across the screen,
    // near the bottom
    ship.setScale(0.25)
    ship.position = CGPoint(x: size.width / 2, y: ship.size.height * 1.25)
    addChild(ship)
    
    // Game physics
    physicsWorld.gravity = CGVector(0, 0) // No gravity in this game...yet!
    physicsWorld.contactDelegate = self // We'll handle contact between physics bodies in this class
    
    spawnAlien() // Start the game with a single alien
  }
  
  // Called exactly once per frame as long as the scene is presented in a view
  // and isn't paused
  override func update(currentTime: CFTimeInterval) {
    var timeSinceLastUpdate = currentTime - lastUpdateTime
    lastUpdateTime = currentTime
    if timeSinceLastUpdate > 1 {
      timeSinceLastUpdate = 1.0 / 60.0
      lastUpdateTime = currentTime
    }
    updateWithTimeSinceLastUpdate(timeSinceLastUpdate)
  }
  
  // Called whenever the user touches the screen
  override func touchesEnded(touches: NSSet, withEvent event: UIEvent) {
    // Select one of the user's touches. Given the event loop's speed, there aren't likely
    // to be more than 1 or 2 touches in the set.
    let touch = touches.anyObject() as UITouch
    let touchLocation = touch.locationInNode(self)
    
    // Reject any shots that are below the ship, or directly to the right or left
    let targetingVector = touchLocation - ship.position
    if targetingVector.y > 0 {
      // FIRE ZE MISSILES!!!
      fireMissile(targetingVector)
    }
  }
  
  // SKPhysicsContactDelegate method: called whenever two physics bodies
  // first contact each other
  func didBeginContact(contact: SKPhysicsContact!) {
    var firstBody: SKPhysicsBody!
    var secondBody: SKPhysicsBody!
    
    // An SKPhysicsContact object is created when 2 physics bodies make contact,
    // and those bodies are referenced by its bodyA and bodyB properties.
    // We want to sort these bodies by their bitmasks so that it's easier
    // to identify which body belongs to which sprite.
    if contact.bodyA.categoryBitMask < contact.bodyB.categoryBitMask {
      firstBody = contact.bodyA
      secondBody = contact.bodyB
    }
    else {
      firstBody = contact.bodyB
      secondBody = contact.bodyA
    }
    
    // We only care about missile-alien contacts.
    // If the contact is missile-alien, firstBody refers to the missile's physics body,
    // and second body refers to the alien's physics body.
    if (firstBody.categoryBitMask & missileCategory) != 0 &&
      (secondBody.categoryBitMask & alienCategory) != 0 {
        destroyAlien(firstBody.node as SKSpriteNode, alien: secondBody.node as SKSpriteNode)
    }
  }
  
  
  // MARK: Game state
  // ================
  
  func updateWithTimeSinceLastUpdate(timeSinceLastUpdate: CFTimeInterval) {
    // If it's been more than a second since we spawned the last alien,
    // spawn a new one
    timeSinceLastAlienSpawned += timeSinceLastUpdate
    if (timeSinceLastAlienSpawned > 0.5) {
      timeSinceLastAlienSpawned = 0
      spawnAlien()
    }
  }
  
  func spawnAlien() {
    
    enum Direction {
      case GoingRight
      case GoingLeft
    }
    
    var alienDirection: Direction!
    var alienSpriteImage: String!
    
    // Randomly pick the alien's origin
    if Int(arc4random_uniform(2)) == 0 {
      alienDirection = Direction.GoingRight
      alienSpriteImage = "alien-going-right"
    }
    else {
      alienDirection = Direction.GoingLeft
      alienSpriteImage = "alien-going-left"
    }
    
    // Create the alien sprite
    let alien = SKSpriteNode(imageNamed: alienSpriteImage)
    
    // Give the alien sprite a physics body
    alien.physicsBody = SKPhysicsBody(rectangleOfSize: alien.size)
    alien.physicsBody?.dynamic = true
    alien.physicsBody?.categoryBitMask = alienCategory
    alien.physicsBody?.contactTestBitMask = missileCategory
    alien.physicsBody?.collisionBitMask = 0
    
    // Set the alien's initial coordinates
    var alienSpawnX: CGFloat!
    var alienEndX: CGFloat!
    if alienDirection == Direction.GoingRight {
      alienSpawnX = -(alien.size.width / 2)
      alienEndX = frame.size.width + (alien.size.width / 2)
    }
    else {
      alienSpawnX = frame.size.width + (alien.size.width / 2)
      alienEndX = -(alien.size.width / 2)
    }
    let minSpawnY = frame.size.height / 3
    let maxSpawnY = (frame.size.height * 0.9) - alien.size.height / 2
    let spawnYRange = UInt32(maxSpawnY - minSpawnY)
    let alienSpawnY = CGFloat(arc4random_uniform(spawnYRange)) + minSpawnY
    alien.position = CGPoint(x: alienSpawnX, y: alienSpawnY)
    
    // Put the alien onscreen
    addChild(alien)
    
    // Set the alien's speed
    let minMoveTime = 2
    let maxMoveTime = 4
    let moveTimeRange = maxMoveTime - minMoveTime
    let moveTime = NSTimeInterval((Int(arc4random_uniform(UInt32(moveTimeRange))) + minMoveTime))
    
    // Send the alien on its way
    let moveAction = SKAction.moveToX(alienEndX, duration: moveTime)
    let cleanUpAction = SKAction.removeFromParent()
    alien.runAction(SKAction.sequence([moveAction, cleanUpAction]))
  }
  
  func fireMissile(targetingVector: CGPoint) {
    // Now that we've confirmed that the shot is "legal", FIRE ZE MISSILES!
    
    // Play shooting sound
    runAction(SKAction.playSoundFileNamed("missile.mp3", waitForCompletion: false))
    
    // Create the missile sprite at the ship's location
    let missile = SKSpriteNode(imageNamed: "missile")
    missile.position.x = ship.position.x
    missile.position.y = ship.position.y + (ship.size.height / 2)
    
    // Give the missile sprite a physics body
    missile.physicsBody = SKPhysicsBody(circleOfRadius: missile.size.width / 2)
    missile.physicsBody?.dynamic = true
    missile.physicsBody?.categoryBitMask = missileCategory
    missile.physicsBody?.contactTestBitMask  = alienCategory
    missile.physicsBody?.collisionBitMask = 0
    missile.physicsBody?.usesPreciseCollisionDetection = true
    
    addChild(missile)
    
    // Calculate the missile's speed and final destination
    let direction = targetingVector.normalized
    let missileVector = direction * 1000
    let missileEndPos = missileVector + missile.position
    let missileSpeed: CGFloat = 500
    let missileMoveTime = size.width / missileSpeed
    
    // Send the missile on its way
    let actionMove = SKAction.moveTo(missileEndPos, duration: NSTimeInterval(missileMoveTime))
    let actionMoveDone = SKAction.removeFromParent()
    missile.runAction(SKAction.sequence([actionMove, actionMoveDone]))
  }
  
  func destroyAlien(missile: SKSpriteNode, alien: SKSpriteNode) {
    // Play explosion sound
    runAction(SKAction.playSoundFileNamed("explosion.wav", waitForCompletion: false))
    
    // When a missile hits an alien, both disappear
    missile.removeFromParent()
    alien.removeFromParent()
  }
  
}